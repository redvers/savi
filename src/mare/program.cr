class Mare::Program
  # TODO: add Package delineation here
  getter types
  
  def initialize
    @types = [] of Type
  end
  
  def find_func!(type_name, func_name)
    @types.find { |t| t.ident.value == type_name }.not_nil!
      .functions.find { |f| f.ident.value == func_name }.not_nil!
  end
  
  class Type
    enum Kind
      Actor
      Class
      FFI
    end
    
    getter kind : Kind
    getter ident : AST::Identifier
    getter properties
    getter functions
    
    def initialize(@kind, @ident)
      @properties = [] of Property
      @functions = [] of Function
    end
  end
  
  class Property
    getter ident : AST::Identifier
    getter ret : AST::Identifier
    getter body : Array(AST::Term)
    
    def initialize(@ident, @ret, @body)
    end
  end
  
  class Function
    getter ident : AST::Identifier
    getter params : AST::Group?
    getter ret : AST::Identifier?
    getter body : Array(AST::Term)
    
    def initialize(@ident, @params, @ret, @body)
    end
  end
end
