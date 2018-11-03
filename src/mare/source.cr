module Mare
  class Source
    property path
    property content
    def initialize(@path : String, @content : String)
    end
    def self.none
      new("(none)", "")
    end
  end
  
  struct SourcePos
    property source
    property row
    property col
    def initialize(@source : Source, @row : Int32, @col : Int32)
    end
    
    # Override inspect to avoid verbosely printing Source#content every time.
    def inspect(io)
      io << "`#{source.path.split("/").last}:#{row}:#{col}`"
    end
  end
end