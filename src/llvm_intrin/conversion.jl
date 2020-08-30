function convert_func(op, T1, W1, T2, W2 = W)
    typ1 = LLVM_TYPES[T1]
    typ2 = LLVM_TYPES[T2]
    vtyp1 = vtype(W1, typ1)
    vtyp2 = vtype(W2, typ2)
    instrs = """
    %res = $op $vtyp2 %0 to $vtyp1
    ret $vtyp1 %res
    """
    quote
        $(Expr(:meta, :inline))
        Vec(llvmcall($instrs, _Vec{$W1,$T1}, Tuple{_Vec{$W2,$T2}}, data(v)))
    end
end
function identity_func(W, T1, T2)
    vtyp1 = vtype(W, LLVM_TYPES[T1])
    instrs = """
    ret $vtyp1 %0
    """
    quote
        $(Expr(:meta, :inline))
        Vec(llvmcall($instrs, _Vec{$W,$T1}, Tuple{_Vec{$W,$T2}}, data(v)))
    end
end

@generated function Vec{W,F}(v::Vec{W,T}) where {W,F<:Union{Float32,Float64},T<:Integer}
    convert_func(T <: Signed ? "sitofp" : "uitofp", W, F, T, (W * sizeof(F)) ÷ sizeof(T))
end

@generated function Vec{W,T}(v::Vec{W,F}) where {W,F<:Union{Float32,Float64},T<:Integer}
    convert_func(T <: Signed ? "fptosi" : "fptoui", T, (W * sizeof(F)) ÷ sizeof(T), F, W)
end
@generated function Vec{W,T1}(v::Vec{W,T2}) where {W,T1<:Integer,T2<:Integer}
    quote
        sz1 = sizeof(T1)::Int; sz2 = sizeof(T2)::Int
        if sz1 < sz2
            convert_func("trunc", W, T1, T2)
        elseif sz1 == 2
            identity_func(W, T1, T2)
        else
            convert_func(((T1 <: Signed) && (T2 <: Signed)) ? "sext" : "zext", W, T1, T2)
        end
    end
end

    

    # for bytes2 in (1,2,4)
    #     bytes2 == bytes1 && break
    #     llvmint2 = "i$(8bytes2)"
    #     jint2 = Symbol(:Int, 8bytes2)
    #     juint2 = Symbol(:UInt, 8bytes2)
    #     expr = :(convert_func("trunc", W, $llvmint2, $jint2, $llvmint, $jint))
    #     @eval @generated Vec{W,$jint2}(v::Vec{W,$jint}) where {W} = $expr
    #     expr = :(convert_func("trunc", W, $llvmint2, $juint2, $llvmint, $jint))
    #     @eval @generated Vec{W,$juint2}(v::Vec{W,$jint}) where {W} = $expr
    #     expr = :(convert_func("trunc", W, $llvmint2, $jint2, $llvmint, $juint))
    #     @eval @generated Vec{W,$jint2}(v::Vec{W,$juint}) where {W} = $expr
    #     expr = :(convert_func("trunc", W, $llvmint2, $juint2, $llvmint, $juint))
    #     @eval @generated Vec{W,$juint2}(v::Vec{W,$juint}) where {W} = $expr

    #     expr = :(convert_func("sext", W, $llvmint, $jint, $llvmint2, $jint2))
    #     @eval @generated Vec{W,$jint}(v::Vec{W,$jint2}) where {W} = $expr
    #     expr = :(convert_func("zext", W, $llvmint, $juint, $llvmint2, $jint2))
    #     @eval @generated Vec{W,$juint}(v::Vec{W,$jint2}) where {W} = $expr
    #     expr = :(convert_func("zext", W, $llvmint, $jint, $llvmint2, $juint2))
    #     @eval @generated Vec{W,$jint}(v::Vec{W,$juint2}) where {W} = $expr
    #     expr = :(convert_func("zext", W, $llvmint, $juint, $llvmint2, $juint2))
    #     @eval @generated Vec{W,$juint}(v::Vec{W,$juint2}) where {W} = $expr
    # end
    # expr = :(identity_func(W, $llvmint, $juint, $jint))
    # @eval @generated Vec{W,$juint}(v::Vec{W,$jint}) where {W} = $expr
    # expr = :(identity_func(W, $llvmint, $jint, $juint))
    # @eval @generated Vec{W,$jint}(v::Vec{W,$juint}) where {W} = $expr
# end

@generated function Vec{W2,Float32}(v::Vec{W,Float64}) where {W,W2}
    @assert W2 == 2W
    convert_func("fptrunc", 2W, :Float32, :Float64, W)
end
@generated function Vec{W,Float64}(v::Vec{W2,Float32}) where {W,W2}
    @assert W2 == 2W
    convert_func("fpext", W, :Float64, :Float32, 2W)
end

Base.convert(::Vec{W,T}, s::T) where {W, T <: NativeTypes} = vbroadcast(Val{W}(), s)
Base.convert(::Vec{W,T}, s::T) where {W, T <: Integer} = vbroadcast(Val{W}(), s)
Base.convert(::Vec{W,T}, s::NativeTypes) where {W, T} = vbroadcast(Val{W}(), T(s))
Base.convert(::Vec{W,T1}, s::T2) where {W, T1 <: Integer, T2 <: Integer} = vbroadcast(Val{W}(), s % T1)


@generated function Base.reinterpret(::Type{T1}, v::Vec{W2,T2}) where {W2, T1 <: NativeTypes, T2}
    W1 = W2 * sizeof(T2) ÷ sizeof(T1)
    Expr(:block, Expr(:meta, :inline), :(reinterpret(Vec{$W1,$T1}, v)))
end
@generated function Base.reinterpret(::Type{Vec{W1,T1}}, v::Vec{W2,T2}) where {W1, W2, T1, T2}
    @assert sizeof(T1) * W1 == W2 * sizeof(T2)
    convert_func("bitcast", W1, LLVM_TYPES[T1], T1, LLVM_TYPES[T2], T2, W2)
end

