class Mare::Compiler::Infer::SubtypingInfo
  def initialize(@this : Program::Type)
    @asserted = Set(Program::Type).new # TODO: use this instead of `is` metadata
    @confirmed = Set(Program::Type).new
    @disproved = Hash(Program::Type, Array(Error::Info)).new
    @temp_assumptions = Set(Program::Type).new
  end
  
  @infer_ready = false
  def infer_ready?; @infer_ready end
  def infer_ready!; @infer_ready = true end
  
  private def this
    @this
  end
  
  # Return true if this type satisfies the requirements of the that type.
  def check(that : Program::Type, errors : Array(Error::Info))
    # TODO: for each return false, carry info about why it was false?
    # Maybe we only want to go to the trouble of collecting this info
    # when it is requested by the caller, so as not to slow the base case.
    
    # If these are literally the same type, we can trivially return true.
    return true if this == that
    
    # We don't have subtyping of concrete types (i.e. class inheritance),
    # so we know this can't possibly be a subtype of that if that is concrete.
    # Note that by the time we've reached this line, we've already
    # determined that the two types are not identical, so we're only
    # concerned with structural subtyping from here on.
    if that.is_concrete?
      errors << {that.ident.pos,
        "a concrete type can't be a subtype of another concrete type"}
      return false
    end
    
    # If we've already done a full check on this type, don't do it again.
    return true if @confirmed.includes?(that)
    if @disproved.has_key?(that)
      errors.concat(@disproved[that])
      return false
    end
    
    # If we have a temp assumption that this is a subtype of that, return true.
    # Otherwise, move forward with the check and add such an assumption.
    # This is done to prevent infinite recursion in the typechecking.
    # The assumption could turn out to be wrong, but no matter what,
    # we don't gain anything by trying to check something that we're already
    # in the middle of checking it somewhere further up the call stack.
    return true if @temp_assumptions.includes?(that)
    @temp_assumptions.add(that)
    
    # Okay, we have to do a full check.
    is_subtype = full_check(that, errors)
    
    # Remove our standing assumption about this being a subtype of that -
    # we have our answer and have no more need for this recursion guard.
    @temp_assumptions.delete(that)
    
    # Save the result of the full check so we don't ever have to do it again.
    if is_subtype
      @confirmed.add(that)
    else
      raise "no errors logged" if errors.empty?
      @disproved[that] = errors
    end
    
    # Finally, return the result.
    is_subtype
  end
  
  private def full_check(that : Program::Type, errors : Array(Error::Info))
    # We can't do anything involving Infer until we've been told it's ready.
    raise "the Infer pass hasn't started yet" unless infer_ready?
    
    # A type only matches an interface if all functions match that interface.
    that.functions.each do |that_func|
      # Hygienic functions are not considered to be real functions for the
      # sake of structural subtyping, so they don't have to be fulfilled.
      next if that_func.has_tag?(:hygienic)
      
      check_func(that, that_func, errors)
    end
    
    errors.empty?
  end
  
  private def check_func(that, that_func, errors)
    # The structural comparison fails if a required method is missing.
    this_func = this.find_func?(that_func.ident.value)
    unless this_func
      errors << {that_func.ident.pos,
        "this function isn't present in the subtype"}
      return false
    end
    
    # Just asserting; we expect find_func? to prevent this.
    raise "found hygienic function" if this_func.has_tag?(:hygienic)
    
    # Get the Infer instance for both this and that function, to compare them.
    this_infer = Infer.from(this, this_func)
    that_infer = Infer.from(that, that_func)
    
    # A constructor can only match another constructor.
    case {this_func.has_tag?(:constructor), that_func.has_tag?(:constructor)}
    when {true, false}
      errors << {this_func.ident.pos,
        "a constructor can't be a subtype of a non-constructor"}
      errors << {that_func.ident.pos,
        "the non-constructor in the supertype is here"}
      return false
    when {false, true}
      errors << {this_func.ident.pos,
        "a non-constructor can't be a subtype of a constructor"}
      errors << {that_func.ident.pos,
        "the constructor in the supertype is here"}
      return false
    end
    
    # A constant can only match another constant.
    case {this_func.has_tag?(:constant), that_func.has_tag?(:constant)}
    when {true, false}
      errors << {this_func.ident.pos,
        "a constant can't be a subtype of a non-constant"}
      errors << {that_func.ident.pos,
        "the non-constant in the supertype is here"}
      return false
    when {false, true}
      errors << {this_func.ident.pos,
        "a non-constant can't be a subtype of a constant"}
      errors << {that_func.ident.pos,
        "the constant in the supertype is here"}
      return false
    end
    
    # Must have the same number of parameters.
    if this_func.param_count != that_func.param_count
      if this_func.param_count < that_func.param_count
        errors << {(this_func.params || this_func.ident).pos,
          "this function has too few parameters"}
      else
        errors << {(this_func.params || this_func.ident).pos,
          "this function has too many parameters"}
      end
      errors << {(that_func.params || that_func.ident).pos,
        "the supertype has #{that_func.param_count} parameters"}
      return false
    end
    
    # TODO: Check receiver rcap (see ponyc subtype.c:240)
    # Covariant receiver rcap for constructors.
    # Contravariant receiver rcap for functions and behaviours.
    
    # Covariant return type.
    this_ret = this_infer.resolve(this_infer.ret_tid)
    that_ret = that_infer.resolve(that_infer.ret_tid)
    unless this_ret < that_ret
      errors << {(this_func.ret || this_func.ident).pos,
        "this function's return type is #{this_ret.show_type}"}
      errors << {(that_func.ret || that_func.ident).pos,
        "it is required to be a subtype of #{that_ret.show_type}"}
    end
    
    # Contravariant parameter types.
    this_func.params.try do |l_params|
      that_func.params.try do |r_params|
        l_params.terms.zip(r_params.terms).each do |(l_param, r_param)|
          l_param_mt = this_infer.resolve(l_param)
          r_param_mt = that_infer.resolve(r_param)
          unless r_param_mt < l_param_mt
            errors << {l_param.pos,
              "this parameter type is #{l_param_mt.show_type}"}
            errors << {r_param.pos,
              "it is required to be a supertype of #{r_param_mt.show_type}"}
          end
        end
      end
    end
    
    errors.empty?
  end
end
