require "../pass/analyze"

##
# WIP: This pass is intended to be a future replacement for the Infer pass,
# but it is still a work in progress and isn't in the main compile path yet.
#
module Savi::Compiler::Types::Edge
  struct Analysis
    getter graph : Graph::Analysis
    property! resolved_return_lower_bound : CompactType
    property! resolved_params_upper_bound : Array(CompactType)

    def initialize(@graph)
    end
  end

  class Visitor < AST::Visitor
    getter analysis : Analysis

    def initialize(@analysis)
    end

    def run_for_type_alias(ctx : Context, t : Program::TypeAlias)
      # TODO: Allow running this pass for more than just the root library.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in the prelude.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_library = ctx.root_library.source_library
      return unless t.ident.pos.source.library == root_library

      raise NotImplementedError.new("run_for_type_alias")
    end

    def run_for_type(ctx : Context, t : Program::Type)
      # TODO: Something?
    end

    def run_for_function(ctx : Context, f : Program::Function)
      # TODO: Allow running this pass for more than just the root library.
      # We restrict this for now while we are building out the pass because
      # we don't want to deal with all of the complicated forms in the prelude.
      # We want to stick to the simple forms in the compiler pass specs for now.
      root_library = ctx.root_library.source_library
      return unless f.ident.pos.source.library == root_library

      # TODO: Sometimes we have a more specific receiver than the owning type.
      var_bindings = {} of TypeVariable => CompactType
      # var_bindings[@analysis.graph.receiver_var] = @analysis.graph.for_self

      @analysis.resolved_return_lower_bound =
        resolve_lower_bound(ctx, @analysis.graph.return_var, var_bindings)

      # TODO: param resolution
    end

    def resolve_lower_bound(ctx, var, var_bindings) : CompactType
      unless var.is_a?(TypeVariable)
        return CompactType.from(@analysis.graph, var, polarity: true)
      end

      # If the caller provided an explicit binding for this particular var,
      # we have no work to do - just return the binding itself.
      explicit_binding = var_bindings[var]?
      return explicit_binding if explicit_binding

      graph = @analysis.graph

      # if graph.lower_bounds_of(var).any?
      #   raise NotImplementedError.new("lower bounds already present")
      # end
      # if graph.upper_bounds_of(var).any?(&.last.is_fundamental?)
      #   raise NotImplementedError.new("upper fundamental bound present")
      # end


      puts
      puts
      puts
      puts @analysis.graph.show_type_variables_list
      puts
      puts var.show
      puts


      compact_analysis = CompactType::Analysis.new
      compact_analysis = CompactType::Analysis.new
      compact = CompactType.from(@analysis.graph, var, polarity: true)

      compact.vars.try(&.each { |bound_var|
        next unless bound_var.is_inner_edge

        call = graph.call_association_of(bound_var).not_nil!
        receiver_ast = call.receiver
        receiver = resolve_lower_bound(ctx, graph[receiver_ast], var_bindings)

        each_implementation_of_call(ctx, receiver, call) { |f_link|
          inner_analysis =
            ctx.types_edge.run_for_func(ctx, f_link.resolve(ctx), f_link)
          pp inner_analysis.resolved_return_lower_bound
          pp :inner_resolved
          # compact.mutably_accept_from(inner_analysis.resolved_return_lower_bound)
        }
      })

      compact
    end

    def each_implementation_of_call(
      ctx : Context,
      receiver_lower_bounds : CompactType,
      call : AST::Call,
      &block : Program::Function::Link ->
    )
      receiver_lower_bounds.nominals.try(&.map { |nominal|
        nominal.link.resolve(ctx).find_func?(call.ident.value)
      })
    end
  end

  # TODO: Refactor - this can't use the generic Pass::Analyze mechanism,
  # because we need to jump back and forth between different function bodies,
  # tracking dependencies on the fly as we do so, so we can save the dynamic
  # list of dependency function links in the cache entry along with the results.
  class Pass < Compiler::Pass::Analyze(Analysis, Analysis, Analysis)
    def analyze_type_alias(ctx, t, t_link) : Analysis
      types_graph = ctx.types_graph[t_link]
      deps = {types_graph}
      prev = ctx.prev_ctx.try(&.types_edge)

      # maybe_from_type_alias_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(*deps))
          .tap(&.run_for_type_alias(ctx, t))
          .analysis.as(Analysis)
      # end
    end

    def analyze_type(ctx, t, t_link) : Analysis
      types_graph = ctx.types_graph[t_link]
      deps = {types_graph}
      prev = ctx.prev_ctx.try(&.types_edge)

      # maybe_from_type_cache(ctx, prev, t, t_link, deps) do
        Visitor.new(Analysis.new(*deps))
          .tap(&.run_for_type(ctx, t))
          .analysis.as(Analysis)
      # end
    end

    def analyze_func(ctx, f, f_link, t_analysis) : Analysis
      types_graph = ctx.types_graph[f_link]
      deps = {types_graph}
      prev = ctx.prev_ctx.try(&.types_edge)

      # maybe_from_func_cache(ctx, prev, f, f_link, deps) do
        Visitor.new(Analysis.new(*deps))
          .tap(&.run_for_function(ctx, f))
          .analysis.as(Analysis)
      # end
    end
  end
end
