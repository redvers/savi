lib LibLLVM
  fun context_set_opaque_pointers = LLVMContextSetOpaquePointers(context : ContextRef, value : Bool)
  fun clear_insertion_position = LLVMClearInsertionPosition(builder : BuilderRef)
  fun get_entry_basic_block = LLVMGetEntryBasicBlock(function : ValueRef) : BasicBlockRef
  fun get_basic_block_terminator = LLVMGetBasicBlockTerminator(basic_block : BasicBlockRef) : ValueRef
  fun position_builder_before = LLVMPositionBuilderBefore(builder : BuilderRef, instruction : ValueRef)
  fun intptr_type_in_context = LLVMIntPtrTypeInContext(ContextRef, TargetDataRef) : TypeRef
  fun build_struct_gep = LLVMBuildStructGEP(builder : BuilderRef, pointer : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun build_frem = LLVMBuildFRem(builder : BuilderRef, lhs : ValueRef, rhs : ValueRef, name : UInt8*) : ValueRef
  fun build_extract_value = LLVMBuildExtractValue(builder : BuilderRef, aggregate : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun build_insert_value = LLVMBuildInsertValue(builder : BuilderRef, aggregate : ValueRef, element : ValueRef, index : UInt32, name : UInt8*) : ValueRef
  fun const_named_struct = LLVMConstNamedStruct(type : TypeRef, values : ValueRef*, num_values : UInt32) : ValueRef
  fun const_inbounds_gep = LLVMConstInBoundsGEP(value : ValueRef, indices : ValueRef*, num_indices : UInt32) : ValueRef
  fun const_bit_cast = LLVMConstBitCast(value : ValueRef, to_type : TypeRef) : ValueRef
  fun set_unnamed_addr = LLVMSetUnnamedAddr(global : ValueRef, is_unnamed_addr : Int32)
  fun is_unnamed_addr = LLVMIsUnnamedAddr(global : ValueRef) : Int32
  fun parse_bitcode_in_context = LLVMParseBitcodeInContext(context : ContextRef, mem_buf : MemoryBufferRef, out_m : ModuleRef*, out_message : UInt8**) : Int32
  fun link_modules = LLVMLinkModules2(dest : ModuleRef, src : ModuleRef) : Int32
  fun strip_module_debug_info = LLVMStripModuleDebugInfo(mod : ModuleRef) : Bool
  fun const_lshr = LLVMConstLShr(lhs : ValueRef, rhs : ValueRef) : ValueRef
  fun const_and = LLVMConstAnd(lhs : ValueRef, rhs : ValueRef) : ValueRef
  fun const_shl = LLVMConstShl(lhs : ValueRef, rhs : ValueRef) : ValueRef
  fun build_is_null = LLVMBuildIsNull(builder : BuilderRef, value : ValueRef, name : UInt8*) : ValueRef
  fun build_is_not_null = LLVMBuildIsNotNull(builder : BuilderRef, value : ValueRef, name : UInt8*) : ValueRef
  fun get_dll_storage_class = LLVMGetDLLStorageClass(global : ValueRef) : LLVM::DLLStorageClass
  fun set_dll_storage_class = LLVMSetDLLStorageClass(global : ValueRef, cls : LLVM::DLLStorageClass)
  fun remove_enum_attribute_at_index = LLVMRemoveEnumAttributeAtIndex(f : ValueRef, idx : AttributeIndex, kind : UInt32)

  enum ByteOrdering
    BigEndian
    LittleEndian
  end

  fun byte_order = LLVMByteOrder(TargetDataRef) : ByteOrdering

  ##
  # Extra functions defined just for Savi go here:
  #

  fun link_for_savi = LLVMLinkForSavi(flavor : UInt8*, argc : Int32, argv : UInt8**, out_ptr : UInt8**, out_size : Int32*) : Bool
  fun optimize_for_savi = LLVMOptimizeForSavi(mod : ModuleRef, wants_full_optimization : Bool)
  fun default_c_flags_for_savi = LLVMDefaultCFlagsForSavi(target : UInt8*, out_args_ptr : UInt8***, out_args_count : Int32*)
  fun compile_c_for_savi = LLVMCompileCForSavi(context : ContextRef, is_debug : Bool, argc : Int32, argv : UInt8**, out_ptr : UInt8**, out_size : Int32*) : ModuleRef
  fun remap_di_directory_for_savi = LLVMRemapDIDirectoryForSavi(mod : ModuleRef, before_dir : UInt8*, after_dir : UInt8*)
end
