require "./pass/analyze"

##
# TODO: Document
#
# This pass is an experimental refactoring of the Infer pass, tracking
# the space of possibilities for a node's type as a Span, so that the Span
# can be resolved quickly later for any given reification.
# The expectation is that this approach will reduce compile times
# and maybe also provide more powerful inference capabilities.
#
# Currently this pass is not used for compilation, unless you use the
# --pass=alt_infer flag when running the `mare` binary.
#
# This pass does not mutate the Program topology.
# This pass does not mutate the AST.
# This pass may raise a compilation error.
# This pass keeps state at the per-function level.
# This pass produces output state at the per-function level.
#
module Mare::Compiler::AltInfer
  struct Span
    alias CK = (Infer::Info | Symbol)
    alias C = Hash(CK, Infer::MetaType)
    alias P = {Infer::MetaType, C?}

    getter points : Array(P)

    def initialize(@points = [] of P)
    end

    def self.simple(mt : Infer::MetaType) : Span
      new([{mt, nil}] of P)
    end

    def self.join(spans : Enumerable(Span))
      new(spans.flat_map(&.points))
    end

    def self.add_cond(a : C?, k : CK, v : Infer::MetaType) : C?
      res = a ? a.dup : C.new
      raise NotImplementedError.new("merge cond keys") if res[k]? && res[k]? != v
      res[k] = v
      res
    end

    def self.get_cond(a : C?, k : CK) : Infer::MetaType?
      return nil unless a
      a[k]?
    end

    def self.get_cond!(a : C?, k : CK) : Infer::MetaType
      get_cond(a, k).not_nil!
    end

    def self.merge_conds(point : P, b : C?) : P?
      mt, a = point
      return {mt, nil} if !a && !b
      return {mt, a} if !b
      return {mt, b} if !a

      res = a ? a.dup : C.new
      b.each do |k, v|
        # TODO: simplify merged conds to remove duplicated conds
        # TODO: remove points with mutually-excluding conds - they are impossible
        existing = res[k]?
        if existing && existing != v
          if k == :f_cap
            return nil # remove points with differing f_cap keys
          else
            raise NotImplementedError.new("merge cond keys")
          end
        else
          res[k] = v
        end
      end
      {mt, res}
    end

    def self.self_with_specified_cap(ctx : Context, infer : Visitor, cap_value : String)
      rt_args = infer
        .type_params_for(ctx, infer.link.type)
        .map { |type_param| Infer::MetaType.new_type_param(type_param) }

      rt = Infer::ReifiedType.new(infer.link.type, rt_args)
      cap_mt = Infer::MetaType::Capability.new_maybe_generic(cap_value)
      mt = Infer::MetaType.new(rt).override_cap(cap_mt)
      Span.simple(mt)
    end

    def self.self_with_reify_cap(ctx : Context, infer : Visitor)
      rt_args = infer
        .type_params_for(ctx, infer.link.type)
        .map { |type_param| Infer::MetaType.new_type_param(type_param) }

      rt = Infer::ReifiedType.new(infer.link.type, rt_args)
      f = infer.func
      f_cap_value = f.cap.value
      f_cap_value = "ref" if f.has_tag?(:constructor)
      f_cap_value = "read" if f_cap_value == "box" # TODO: figure out if we can remove this Pony-originating semantic hack
      Span.new(
        Infer::MetaType::Capability.new_maybe_generic(f_cap_value).each_cap.map do |cap|
          cap_mt = Infer::MetaType.new(cap)
          {Infer::MetaType.new(rt).override_cap(cap_mt), { :f_cap.as(CK) => cap_mt }}.as(P)
        end.to_a
      )
    end

    def self.self_ephemeral_with_cap(ctx : Context, infer : Visitor, cap : String)
      rt_args = infer
        .type_params_for(ctx, infer.link.type)
        .map { |type_param| Infer::MetaType.new_type_param(type_param) }

      rt = Infer::ReifiedType.new(infer.link.type, rt_args)
      mt = Infer::MetaType.new(rt, cap).ephemeralize
      new([{mt, nil}] of P)
    end

    def filter_remove_cond(cond_key : CK)
      Span.new(
        points.map do |mt, conds|
          should_keep = conds ? (yield conds[cond_key]?) : (yield nil)

          if should_keep
            {mt, conds ? conds.reject(cond_key).as(C?) : nil}
          end
        end.compact
      )
    end

    def filter_remove_f_cap(call_mt_cap : Infer::MetaType, call_func : Program::Function)
      exact_span = filter_remove_cond(:f_cap) { |f_cap|
        !f_cap || f_cap == call_mt_cap
      }
      return exact_span unless exact_span.points.empty?

      filter_remove_cond(:f_cap) { |f_cap|
        !f_cap ||
        f_cap == call_mt_cap ||
        call_mt_cap.cap_only_inner.subtype_of?(f_cap.not_nil!.cap_only_inner) ||
        call_func.has_tag?(:constructor) || # TODO: better way to do this?
        call_mt_cap.inner == Infer::MetaType::Capability::ISO || # TODO: better way to handle auto recovery ||
        call_mt_cap.inner == Infer::MetaType::Capability::TRN # TODO: better way to handle auto recovery
      }
    end

    def expand : Span
      Span.new(points.flat_map { |mt, conds| (yield mt, conds) })
    end

    def transform : Span
      Span.new(points.map { |mt, conds| (yield mt, conds) })
    end

    def transform_mt : Span
      Span.new(points.map { |mt, conds| {(yield mt), conds} })
    end

    def with_prior_conds(conds : C?) : Span
      Span.new(points.map { |point| Span.merge_conds(point, conds) }.compact)
    end

    def combine_mt(other : Span) : Span
      Span.new(
        points.flat_map do |mt, conds|
          other.with_prior_conds(conds).points.map do |other_mt, merged_conds|
            {(yield mt, other_mt), merged_conds}
          end
        end
      )
    end

    def combine_mts(others : Array(Span)) : Span
      combos = points.map { |mt, conds| {mt, [] of Infer::MetaType, conds} }
      others.each do |other|
        combos = combos.flat_map do |mt, other_mts, conds|
          other.with_prior_conds(conds).points.map do |other_mt, merged_conds|
            {mt, other_mts + [other_mt], merged_conds}
          end
        end
      end
      Span.new(
        combos.map { |mt, other_mts, conds| {(yield mt, other_mts), conds} }
      )
    end

    def self.combine_mts(spans : Array(Span))
      return Span.new if spans.empty?
      spans[0].combine_mts(spans[1..-1]) do |mt, other_mts|
        yield [mt] + other_mts
      end
    end
  end

  struct Analysis
    def initialize
      @spans = {} of Infer::Info => Span
    end

    def [](info : Infer::Info); @spans[info]; end
    def []?(info : Infer::Info); @spans[info]?; end
    protected def []=(info, span); @spans[info] = span; end
  end

  class Visitor < Mare::AST::Visitor
    getter analysis
    protected getter func
    protected getter link
    protected getter refer_type
    protected getter refer_type_parent
    protected getter classify
    protected getter pre_infer

    protected def f_analysis; pre_infer; end # TODO: remove this alias

    def initialize(
      @func : Program::Function,
      @link : Program::Function::Link,
      @analysis : Analysis,
      @refer_type : ReferType::Analysis,
      @refer_type_parent : ReferType::Analysis,
      @classify : Classify::Analysis,
      @type_context : TypeContext::Analysis,
      @pre_infer : PreInfer::Analysis,
    )
      @substs_for_layer = Hash(TypeContext::Layer, Hash(Infer::TypeParam, Infer::MetaType)).new
    end

    def resolve(ctx : Context, info : Infer::Info) : Span
      @analysis[info]? || begin
        ast = @pre_infer.node_for?(info)
        substs = substs_for_layer(ctx, ast) if ast

        # If this info resolves as a conduit, resolve the conduit,
        # and do not save the result locally for this span.
        conduit = info.as_conduit?
        return conduit.resolve_span!(ctx, self) if conduit

        span = info.resolve_span!(ctx, self)
        span = span.transform_mt(&.substitute_type_params(substs)) if substs

        @analysis[info] = span

        span
      rescue Compiler::Pass::Analyze::ReentranceError
        kind = info.is_a?(Infer::DynamicInfo) ? " #{info.describe_kind}" : ""
        Error.at info.pos,
          "This#{kind} needs an explicit type; it could not be inferred"
      end
    end

    def type_params_for(ctx : Context, type_link : Program::Type::Link) : Array(Infer::TypeParam)
      type_link.resolve(ctx).params.try(&.terms.map { |type_param|
        ident = AST::Extract.type_param(type_param).first
        ref = refer_type[ident]? || refer_type_parent[ident]
        Infer::TypeParam.new(ref.as(Refer::TypeParam))
      }) || [] of Infer::TypeParam
    end

    def lookup_type_param_bound(ctx : Context, type_param : Infer::TypeParam)
      ref = type_param.ref
      raise "lookup on wrong visitor" unless ref.parent_link == link.type
      span = type_expr_span(ctx, ref.bound)
      Infer::MetaType.new_union(span.points.map(&.first)) # TODO: return span instead of MetaType
    end

    def substs_for(ctx : Context, rt : Infer::ReifiedType) : Hash(Infer::TypeParam, Infer::MetaType)
      type_params_for(ctx, rt.link).zip(rt.args).to_h
    end

    def substs_for_layer(ctx : Context, node : AST::Node) : Hash(Infer::TypeParam, Infer::MetaType)?
      layer = @type_context[node]?
      return nil unless layer

      @substs_for_layer[layer] ||= (
        # TODO: also handle negative conditions
        layer.all_positive_conds.compact_map do |cond|
          cond_info = @pre_infer[cond]
          case cond_info
          when Infer::TypeParamCondition
            type_param = Infer::TypeParam.new(cond_info.refine)
            # TODO: carry through entire span, not just union of its MetaTypes
            meta_type = Infer::MetaType.new_type_param(type_param).intersect(
              Infer::MetaType.new_union(
                resolve(ctx, cond_info.refine_type).points.map(&.first)
              )
            )
            {type_param, meta_type}
          # TODO: also handle other conditions?
          else nil
          end
        end.to_h
      )
    end

    def depends_on_call_ret_span(ctx, other_rt, other_f, other_f_link)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre[other_f.ident]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_param_span(ctx, other_rt, other_f, other_f_link, index)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre[AST::Extract.params(other_f.params)[index].first]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_yield_in_span(ctx, other_rt, other_f, other_f_link)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre.yield_in_info.not_nil!]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def depends_on_call_yield_out_span(ctx, other_rt, other_f, other_f_link, index)
      deps = ctx.alt_infer_edge.gather_deps_for_func(ctx, other_f, other_f_link)
      visitor = Visitor.new(other_f, other_f_link, Analysis.new, *deps)

      # TODO: Track dependencies and invalidate cache based on those.
      other_pre = deps.last
      other_analysis = ctx.alt_infer_edge.run_for_func(ctx, other_f, other_f_link)
      other_analysis[other_pre.yield_out_infos[index]]
      .transform_mt(&.substitute_type_params(visitor.substs_for(ctx, other_rt)))
    end

    def run_edge(ctx : Context)
      func.params.try do |params|
        params.terms.each { |param| resolve(ctx, @pre_infer[param]) }
      end

      resolve(ctx, @pre_infer[ret])

      @pre_infer.yield_in_info.try { |info| resolve(ctx, info) }
      @pre_infer.yield_out_infos.each { |info| resolve(ctx, info) }
    end

    def run(ctx : Context)
      func_body = func.body
      resolve(ctx, @pre_infer[func_body]) if func_body

      @pre_infer.each_info.each { |info| resolve(ctx, info) }
    end

    def ret
      # The ident is used as a fake local variable that represents the return.
      func.ident
    end

    def prelude_reified_type(ctx : Context, name : String, args = [] of Infer::MetaType)
      Infer::ReifiedType.new(ctx.namespace.prelude_type(name), args)
    end

    def prelude_type_span(ctx : Context, name : String)
      Span.simple(Infer::MetaType.new(prelude_reified_type(ctx, name)))
    end

    def type_expr_cap(node : AST::Identifier) : Infer::MetaType::Capability
      case node.value
      when "iso", "trn", "val", "ref", "box", "tag", "non"
        Infer::MetaType::Capability.new(node.value)
      when "any", "alias", "send", "share", "read"
        Infer::MetaType::Capability.new_generic(node.value)
      else
        Error.at node, "This type couldn't be resolved"
      end
    end

    # An identifier type expression must refer to a type.
    def type_expr_span(ctx : Context, node : AST::Identifier) : Span
      ref = refer_type[node]?
      case ref
      when Refer::Self
        Span.self_with_reify_cap(ctx, self)
      when Refer::Type
        Span.simple(Infer::MetaType.new(Infer::ReifiedType.new(ref.link)))
      # when Refer::TypeAlias
      #   Infer::MetaType.new_alias(reified_type_alias(ref.link_alias))
      when Refer::TypeParam
        Span.simple(Infer::MetaType.new_type_param(Infer::TypeParam.new(ref)))
      when nil
        Span.simple(Infer::MetaType.new(type_expr_cap(node)))
      else
        raise NotImplementedError.new(ref.inspect)
      end
    end

    # An relate type expression must be an explicit capability qualifier.
    def type_expr_span(ctx : Context, node : AST::Relate) : Span
      if node.op.value == "'"
        cap_ident = node.rhs.as(AST::Identifier)
        case cap_ident.value
        when "aliased"
          type_expr_span(ctx, node.lhs).transform_mt do |lhs_mt|
            lhs_mt.alias
          end
        else
          cap = type_expr_cap(cap_ident)
          type_expr_span(ctx, node.lhs).transform_mt do |lhs_mt|
            lhs_mt.override_cap(cap)
          end
        end
      elsif node.op.value == "->"
        lhs = type_expr_span(ctx, node.lhs)
        rhs = type_expr_span(ctx, node.rhs)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.viewed_from(lhs_mt) }
      elsif node.op.value == "->>"
        lhs = type_expr_span(ctx, node.lhs)
        rhs = type_expr_span(ctx, node.rhs)
        lhs.combine_mt(rhs) { |lhs_mt, rhs_mt| rhs_mt.extracted_from(lhs_mt) }
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "|" group must be a union of type expressions, and a "(" group is
    # considered to be just be a single parenthesized type expression (for now).
    def type_expr_span(ctx : Context, node : AST::Group) : Span
      if node.style == "|"
        spans = node.terms
          .select { |t| t.is_a?(AST::Group) && t.terms.size > 0 }
          .map { |t| type_expr_span(ctx, t).as(Span) }

        Span.combine_mts(spans) { |mts| Infer::MetaType.new_union(mts) }
      elsif node.style == "(" && node.terms.size == 1
        type_expr_span(ctx, node.terms.first)
      else
        raise NotImplementedError.new(node.to_a.inspect)
      end
    end

    # A "(" qualify is used to add type arguments to a type.
    def type_expr_span(ctx : Context, node : AST::Qualify) : Span
      raise NotImplementedError.new(node.to_a) unless node.group.style == "("

      target_span = type_expr_span(ctx, node.term)
      arg_spans = node.group.terms.map do |t|
        type_expr_span(ctx, t).as(Span)
      end

      target_span.combine_mts(arg_spans) do |target_mt, arg_mts|
        target_inner = target_mt.inner
        if target_inner.is_a?(Infer::MetaType::Nominal) \
        && target_inner.defn.is_a?(Infer::ReifiedTypeAlias)
          link = target_inner.defn.as(Infer::ReifiedTypeAlias).link
          Infer::MetaType.new(Infer::ReifiedTypeAlias.new(link, arg_mts))
        else
          link = target_mt.single!.link
          cap = begin target_mt.cap_only rescue nil end
          mt = Infer::MetaType.new(Infer::ReifiedType.new(link, arg_mts))
          mt = mt.override_cap(cap) if cap
          mt
        end
      end
    end

    # All other AST nodes are unsupported as type expressions.
    def type_expr_span(ctx : Context, node : AST::Node) : Span
      raise NotImplementedError.new(node.to_a)
    end
  end

  # The "edge" version of the pass only resolves the minimal amount of nodes
  # needed to understand the type signature of each function in the program.
  class PassEdge < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer_edge)

      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, Analysis.new, *deps).tap(&.run_edge(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end

  # This pass picks up the Analysis wherever the PassEdge last left off,
  # resolving all of the other nodes that weren't reached in edge analysis.
  class Pass < Compiler::Pass::Analyze(Nil, Nil, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Nil
      nil
    end

    def analyze_type(ctx, t, t_link) : Nil
      nil
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      deps = gather_deps_for_func(ctx, f, f_link)
      prev = ctx.prev_ctx.try(&.alt_infer)

      edge_analysis = ctx.alt_infer_edge[f_link]
      maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(f, f_link, edge_analysis, *deps).tap(&.run(ctx)).analysis
      end
    end

    def gather_deps_for_func(ctx, f, f_link)
      refer_type = ctx.refer_type[f_link]
      refer_type_parent = ctx.refer_type[f_link.type]
      classify = ctx.classify[f_link]
      type_context = ctx.type_context[f_link]
      pre_infer = ctx.pre_infer[f_link]

      {refer_type, refer_type_parent, classify, type_context, pre_infer}
    end
  end
end
