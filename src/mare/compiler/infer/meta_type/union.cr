struct Mare::Compiler::Infer::MetaType::Union
  getter caps : Set(Capability)?
  getter terms : Set(Nominal)?
  getter anti_terms : Set(AntiNominal)?
  getter intersects : Set(Intersection)?
  
  def initialize(@caps = nil, @terms = nil, @anti_terms = nil, @intersects = nil)
    count = 0
    count += caps.try(&.size) || 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    count += intersects.try(&.size) || 0
    
    raise "too few terms: #{inspect}" if count <= 1
    
    raise "empty caps" if caps && caps.try(&.empty?)
    raise "empty terms" if terms && terms.try(&.empty?)
    raise "empty anti_terms" if anti_terms && anti_terms.try(&.empty?)
    raise "empty intersects" if intersects && intersects.try(&.empty?)
  end
  
  # This function works like .new, but it accounts for cases where there
  # aren't enough terms, anti-terms, and intersections to build a real Union.
  # Returns Unsatisfiable if no terms or anti-terms are supplied.
  def self.build(
    caps : Set(Capability)? = nil,
    terms : Set(Nominal)? = nil,
    anti_terms : Set(AntiNominal)? = nil,
    intersects : Set(Intersection)? = nil,
  ) : Inner
    count = 0
    count += caps.try(&.size) || 0
    count += terms.try(&.size) || 0
    count += anti_terms.try(&.size) || 0
    count += intersects.try(&.size) || 0
    
    case count
    when 0 then Unsatisfiable.instance
    when 1 then caps.try(&.first?) || terms.try(&.first?) ||
                anti_terms.try(&.first?) || intersects.not_nil!.first
    else
      caps = nil if caps && caps.empty?
      terms = nil if terms && terms.empty?
      anti_terms = nil if anti_terms && anti_terms.empty?
      intersects = nil if intersects && intersects.empty?
      new(caps, terms, anti_terms, intersects)
    end
  end
  
  def inspect(io : IO)
    first = true
    io << "("
    
    caps.not_nil!.each do |cap|
      io << " | " unless first; first = false
      cap.inspect(io)
    end if caps
    
    terms.not_nil!.each do |term|
      io << " | " unless first; first = false
      term.inspect(io)
    end if terms
    
    anti_terms.not_nil!.each do |anti_term|
      io << " | " unless first; first = false
      anti_term.inspect(io)
    end if anti_terms
    
    intersects.not_nil!.each do |intersect|
      io << " | " unless first; first = false
      intersect.inspect(io)
    end if intersects
    
    io << ")"
  end
  
  def hash : UInt64
    hash = self.class.hash
    hash ^= caps.not_nil!.hash if caps
    hash ^= (terms.not_nil!.hash * 15) if terms
    hash ^= (anti_terms.not_nil!.hash * 31) if anti_terms
    hash ^= (intersects.not_nil!.hash * 63) if intersects
    hash
  end
  
  def ==(other)
    other.is_a?(Union) &&
    caps == other.caps &&
    terms == other.terms &&
    anti_terms == other.anti_terms &&
    intersects == other.intersects
  end
  
  def each_reachable_defn : Iterator(Program::Type)
    iter = ([] of Program::Type).each
    iter = iter.chain(terms.not_nil!.each.map(&.defn)) if terms
    iter = iter.chain(anti_terms.not_nil!.each.map(&.defn)) if anti_terms # TODO: is an anti-nominal actually reachable?
    iter = iter.chain(
      intersects.not_nil!.map(&.each_reachable_defn).flat_map(&.to_a).each
    ) if intersects
    
    iter
  end
  
  def find_callable_func_defns(name : String)
    # Every term in the union must have an implementation of the call.
    list = [] of Tuple(Program::Type, Program::Function)
    terms.not_nil!.each do |term|
      result = term.find_callable_func_defns(name)
      return nil unless result
      list.concat(result)
    end if terms
    intersects.not_nil!.each do |intersect|
      result = intersect.find_callable_func_defns(name)
      return nil unless result
      list.concat(result)
    end if intersects
    list
  end
  
  def negate : Inner
    # De Morgan's Law:
    # The negation of a union is the intersection of negations of its terms.
    result = nil
    caps.not_nil!.each do |cap|
      cap = cap.negate
      result = result ? result.intersect(cap) : cap
      return result if result.is_a?(Unsatisfiable)
    end if caps
    terms.not_nil!.each do |term|
      term = term.negate
      result = result ? result.intersect(term) : term
      return result if result.is_a?(Unsatisfiable)
    end if terms
    anti_terms.not_nil!.each do |anti_term|
      anti_term = anti_term.negate
      result = result ? result.intersect(anti_term) : anti_term
      return result if result.is_a?(Unsatisfiable)
    end if anti_terms
    intersects.not_nil!.each do |intersect|
      intersect = intersect.negate
      result = result ? result.intersect(intersect) : intersect
      return result if result.is_a?(Unsatisfiable)
    end if intersects
    
    result.not_nil!
  end
  
  def intersect(other : Unconstrained)
    self
  end
  
  def intersect(other : Unsatisfiable)
    other
  end
  
  def intersect(
    other : (Capability | Nominal | AntiNominal | Intersection | Union)
  )
    # Intersect the other with each term that we contain in the union,
    # discarding any results that come back as Unsatisfiable intersections.
    results = [] of Inner
    caps.not_nil!.each do |cap|
      result = other.intersect(cap)
      results << result unless result.is_a?(Unsatisfiable)
    end if caps
    terms.not_nil!.each do |term|
      result = other.intersect(term)
      results << result unless result.is_a?(Unsatisfiable)
    end if terms
    anti_terms.not_nil!.each do |anti_term|
      result = other.intersect(anti_term)
      results << result unless result.is_a?(Unsatisfiable)
    end if anti_terms
    intersects.not_nil!.each do |intersect|
      result = other.intersect(intersect)
      results << result unless result.is_a?(Unsatisfiable)
    end if intersects
    
    # Finally, unite all of the intersections together into their union.
    result = Unsatisfiable.instance
    results.each { |x| result = result.unite(x) }
    result
  end
  
  def unite(other : Unconstrained)
    other
  end
  
  def unite(other : Unsatisfiable)
    self
  end
  
  def unite(other : Capability)
    # No change if we've already united with this cap.
    return self if caps && caps.not_nil!.includes?(other)
    
    # Otherwise, create a new union that adds this type.
    new_caps = 
      if caps
        caps.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Union.new(new_caps, terms, anti_terms, intersects)
  end
  
  def unite(other : Nominal)
    # No change if we've already united with this type.
    return self if terms && terms.not_nil!.includes?(other)
    
    # Unconstrained if we have already have an anti-term for this type.
    return Unconstrained.instance \
      if anti_terms && anti_terms.not_nil!.includes?(AntiNominal.new(other.defn))
    
    # Otherwise, create a new union that adds this type.
    new_terms = 
      if terms
        terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Union.new(caps, new_terms, anti_terms, intersects)
  end
  
  def unite(other : AntiNominal)
    # No change if we've already united with this anti-type.
    return self if anti_terms && anti_terms.not_nil!.includes?(other)
    
    # Unconstrained if we have already have a term for this anti-type.
    return Unconstrained.instance \
      if terms && terms.not_nil!.includes?(Nominal.new(other.defn))
    
    # Unconstrained if there are two non-identical concrete anti-types.
    return Unconstrained.instance \
      if other.is_concrete? \
        && anti_terms && anti_terms.not_nil!.any?(&.is_concrete?)
    
    # Add this to existing anti-terms (if any) and create the union.
    new_anti_terms =
      if anti_terms
        anti_terms.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Union.new(caps, terms, new_anti_terms, intersects)
  end
  
  def unite(other : Intersection)
    # No change if we already have an equivalent intersection.
    return self if intersects && intersects.not_nil!.includes?(other)
    
    # Add this to existing anti-terms (if any) and create the union.
    new_intersects =
      if intersects
        intersects.not_nil!.dup.add(other)
      else
        [other].to_set
      end
    Union.new(caps, terms, anti_terms, new_intersects)
  end
  
  def unite(other : Union)
    # Intersect each individual term of other into this running union.
    # If the result becomes Unconstrained, return so immediately.
    result : Inner = self
    other.caps.not_nil!.each do |term|
      result = result.unite(term)
      return result if result.is_a?(Unconstrained)
    end if other.caps
    other.terms.not_nil!.each do |term|
      result = result.unite(term)
      return result if result.is_a?(Unconstrained)
    end if other.terms
    other.anti_terms.not_nil!.each do |anti_term|
      result = result.unite(anti_term)
      return result if result.is_a?(Unconstrained)
    end if other.anti_terms
    other.intersects.not_nil!.each do |intersect|
      result = result.unite(intersect)
      return result if result.is_a?(Unconstrained)
    end if other.intersects
    
    result
  end
  
  def subtype_of?(other : Capability) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(other : Capability) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(other : (Nominal | AntiNominal | Intersection)) : Bool
    # This union is a subtype of the other if and only if
    # all terms in the union are subtypes of that other.
    result = true
    result &&= caps.not_nil!.all?(&.subtype_of?(other)) if caps
    result &&= terms.not_nil!.all?(&.subtype_of?(other)) if terms
    result &&= anti_terms.not_nil!.all?(&.subtype_of?(other)) if anti_terms
    result &&= intersects.not_nil!.all?(&.subtype_of?(other)) if intersects
    result
  end
  
  def supertype_of?(other : (Nominal | AntiNominal | Intersection)) : Bool
    # This union is a supertype of the given other if and only if
    # any term in the union qualifies as a supertype of that other.
    result = false
    result ||= caps.not_nil!.any?(&.supertype_of?(other)) if caps
    result ||= terms.not_nil!.any?(&.supertype_of?(other)) if terms
    result ||= anti_terms.not_nil!.any?(&.supertype_of?(other)) if anti_terms
    result ||= intersects.not_nil!.any?(&.supertype_of?(other)) if intersects
    result
  end
  
  def subtype_of?(other : Union) : Bool
    raise NotImplementedError.new([self, :subtype_of?, other].inspect)
  end
  
  def supertype_of?(other : Union) : Bool
    raise NotImplementedError.new([self, :supertype_of?, other].inspect)
  end
  
  def subtype_of?(other : (Unconstrained | Unsatisfiable)) : Bool
    other.supertype_of?(self) # delegate to the other class via symmetry
  end
  
  def supertype_of?(other : (Unconstrained | Unsatisfiable)) : Bool
    other.subtype_of?(self) # delegate to the other class via symmetry
  end
end