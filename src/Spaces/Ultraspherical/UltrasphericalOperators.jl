##  Jacobi Operator

recB{T}(::Type{T},::Ultraspherical,::)=zero(T)

recA{T}(::Type{T},::Chebyshev,k)=2one(T)
recC{T}(::Type{T},::Chebyshev,k)=one(T)   # one(T) ensures we get correct type

recA{T,λ}(::Type{T},::Ultraspherical{λ},k)=(2*(k+λ))/(k+one(T))   # one(T) ensures we get correct type
recC{T,λ}(::Type{T},::Ultraspherical{λ},k)=(k-one(T)+2λ)/(k+one(T))   # one(T) ensures we get correct type

# x p_k
recα{T}(::Type{T},::Ultraspherical,::)=zero(T)

recβ{T}(::Type{T},::Chebyshev,k)=ifelse(k==1,one(T),one(T)/2)   # one(T) ensures we get correct type,ifelse ensures inlining
recγ{T}(::Type{T},::Chebyshev,k)=one(T)/2   # one(T) ensures we get correct type

recβ{T,λ}(::Type{T},::Ultraspherical{λ},k)=k/(2*(k-one(T)+λ))   # one(T) ensures we get correct type
recγ{T,λ}(::Type{T},::Ultraspherical{λ},k)=(k-2+2λ)/(2*(k-one(T)+λ))   # one(T) ensures we get correct type



## Evaluation

function evaluatechebyshev{T<:Number}(n::Integer,x::T)
    if n == 1
        [one(T)]
    else
        p = zeros(T,n)
        p[1] = one(T)
        p[2] = x

        for j=2:n-1
            p[j+1] = 2x*p[j] - p[j-1]
        end

        p
    end
end





##TODO: the overloading as both vector and row vector may be confusing
function Base.getindex{DD<:Interval}(op::Evaluation{Chebyshev{DD},Bool},k::Range)
    T=eltype(op)
    x = op.x
    d = domain(op)
    p = op.order
    cst = (2/(d.b-d.a))^p
    n=length(k)

    if x
        ret = ones(T,n)
    else
        ret = Array(T,n)
        k1=1-first(k)
        @simd for j=k
            @inbounds ret[j+k1]=(-1)^(p+1)*(-one(T))^j
        end
    end

    for m=0:p-1
        k1=1-first(k)
        @simd for j=k
            @inbounds ret[j+k1] *= (j-1)^2-m^2
        end
        BLAS.scal!(n, 1/(2m+1), ret,1)
    end

    BLAS.scal!(n,cst,ret,1)
end

function Base.getindex{DD<:Interval,M<:Real}(op::Evaluation{Chebyshev{DD},M},k::Range)
    if op.order == 0
        evaluatechebyshev(k[end],tocanonical(domain(op),op.x))[k]
    else
        error("Only zero–second order implemented")
    end
end



## Multiplication
# these are special cases


Base.stride{U<:Ultraspherical,V<:Ultraspherical}(M::ConcreteMultiplication{U,V})=stride(M.f)


function chebmult_getindex(cfs::Vector,k::Integer,j::Integer)
    n=length(cfs)

    ret=zero(eltype(cfs))

    # Toeplitz part
    if k == j
        ret += cfs[1]
    elseif k > j && k-j+1 ≤ n
        ret += cfs[k-j+1]/2
    elseif k < j && j-k+1 ≤ n
        ret += cfs[j-k+1]/2
    end

    # Hankel part
    if k ≥ 2 && k+j-1 ≤ n
        ret += cfs[k+j-1]/2
    end

    ret
end


getindex{T,C<:Chebyshev}(M::ConcreteMultiplication{C,C,T},k::Integer,j::Integer) =
    chebmult_getindex(coefficients(M.f),k,j)


function getindex{D,T,C<:Chebyshev}(M::ConcreteMultiplication{C,Ultraspherical{1,D},T},k::Integer,j::Integer)
    cfs=coefficients(M.f)
    toeplitz_getindex(.5cfs,k,j)+hankel_getindex(-.5cfs[3:end],k,j)
end



function addentries!{λ,PS<:PolynomialSpace,D,T}(M::ConcreteMultiplication{Ultraspherical{λ,D},PS,T},A,kr::UnitRange,::Colon)
    a=coefficients(M.f)
    for k=kr
        A[k,k]=a[1]
    end

    if length(a) > 1
        jkr=max(1,kr[1]-length(a)+1):kr[end]+length(a)-1

        J=subview(Recurrence(domainspace(M)),jkr,jkr)
        C1=2λ*J
        addentries!(C1,a[2],A,kr,:)
        C0=isbeye(jkr)

        for k=1:length(a)-2
            C1,C0=2(k+λ)/(k+one(T))*J*C1-(k+2λ-one(T))/(k+one(T))*C0,C1
            addentries!(C1,a[k+2],A,kr,:)
        end
    end

    A
end


function addentries!{PS<:PolynomialSpace,T,C<:Chebyshev}(M::ConcreteMultiplication{C,PS,T},A,kr::UnitRange,::Colon)
    a=coefficients(M.f)

    for k=kr
        A[k,k]=a[1]
    end

    if length(M.f) > 1
        sp=M.space
        jkr=max(1,kr[1]-length(a)+1):kr[end]+length(a)-1

        #Multiplication is transpose
        J=subview(Recurrence(sp),jkr,jkr)
        C1=J
        addentries!(C1,a[2],A,kr,:)
        C0=isbeye(jkr)

        for k=1:length(a)-2
            C1,C0=2J*C1-C0,C1
            addentries!(C1,a[k+2],A,kr,:)
        end
    end

    A
end





## Derivative


#Derivative(k::Integer,d::IntervalDomain)=Derivative(k-1:k,d)
#Derivative(d::IntervalDomain)=Derivative(1,d)

Derivative{λ,DD<:Interval}(sp::Ultraspherical{λ,DD},order::Integer)=ConcreteDerivative(sp,order)
Integral{λ,DD<:Interval}(sp::Ultraspherical{λ,DD},order::Integer)=ConcreteIntegral(sp,order)


rangespace{λ,DD<:Interval}(D::ConcreteDerivative{Ultraspherical{λ,DD}})=Ultraspherical{λ+D.order}(domain(D))
bandinds{λ,DD<:Interval}(D::ConcreteDerivative{Ultraspherical{λ,DD}})=0,D.order
bandinds{λ,DD<:Interval}(D::ConcreteIntegral{Ultraspherical{λ,DD}})=-D.order,0
Base.stride{λ,DD<:Interval}(D::ConcreteDerivative{Ultraspherical{λ,DD}})=D.order


function getindex{λ,DD<:Interval,K,T}(D::ConcreteDerivative{Ultraspherical{λ,DD},K,T},k::Integer,j::Integer)
    m=D.order
    d=domain(D)

    if λ == 0 && j==k+m
        C=.5pochhammer(1.,m-1)*(4./(d.b-d.a)).^m
        (C*(m+k-one(T)))::T
    elseif j==k+m
        (pochhammer(one(T)*λ,m)*(4./(d.b-d.a)).^m)::T
    else
        zero(T)
    end
end


## Integral

function linesum{λ,DD<:Interval}(f::Fun{Ultraspherical{λ,DD}})
    d=domain(f)
    sum(Fun(f.coefficients,Ultraspherical{λ}()))*length(d)/2
end



# TODO: include in addentries! to speed up
Integral{DD<:Interval}(sp::Chebyshev{DD},m::Integer)=IntegralWrapper(
    TimesOperator([Integral(Ultraspherical{m}(domain(sp)),m),Conversion(sp,Ultraspherical{m}(domain(sp)))]),m)

rangespace{λ,DD<:Interval}(D::ConcreteIntegral{Ultraspherical{λ,DD}})=Ultraspherical{λ-D.order}(domain(D))

function getindex{λ,DD<:Interval,T}(D::ConcreteIntegral{Ultraspherical{λ,DD},T},k::Integer,j::Integer)
    m=D.order
    d=domain(D)
    @assert m<=λ

    if λ == 1 && k==j+1
        C = .5(d.b-d.a)
        C./(k-one(T))
    elseif λ > 1 && k==j+m
        pochhammer(one(T)*λ,-m)*(.25(d.b-d.a))^m
    else
        zero(T)
    end
end



## Conversion Operator




function Conversion{a,b,DD}(A::Ultraspherical{a,DD},B::Ultraspherical{b,DD})
    @assert b >= a

    if b==a
        eye(A)
    elseif b==a+1
        ConcreteConversion(A,B)
    else
        d=domain(A)
        ConversionWrapper(TimesOperator(Conversion(Ultraspherical{b-1,DD}(d),B),Conversion(A,Ultraspherical{b-1,DD}(d))))
    end
end


function getindex{DD,C<:Chebyshev,T}(M::ConcreteConversion{C,Ultraspherical{1,DD},T},k::Integer,j::Integer)
    if k==j==1
        one(T)
    elseif k==j
        one(T)/2
    elseif j==k+2
        -one(T)/2
    else
        zero(T)
    end
end


function getindex{m,λ,DD,T}(M::ConcreteConversion{Ultraspherical{m,DD},Ultraspherical{λ,DD},T},k::Integer,j::Integer)
    #  we can assume that λ==m+1
    c=λ-one(T)  # this supports big types
    if k==j
        c/(k - 2 + λ)
    elseif j==k+2
        -c/(k + λ)
    else
        zero(T)
    end
end

bandinds{m,DD,λ}(C::ConcreteConversion{Ultraspherical{m,DD},Ultraspherical{λ,DD}})=0,2
Base.stride{m,λ,DD}(C::ConcreteConversion{Ultraspherical{m,DD},Ultraspherical{λ,DD}})=2


## coefficients

# return the space that has banded Conversion to the other
function conversion_rule{aorder,border}(a::Ultraspherical{aorder},b::Ultraspherical{border})
    if domainscompatible(a,b)
        aorder < border?a:b
    else
        NoSpace()
    end
end


coefficients(g::Vector,::Ultraspherical{1},::Chebyshev)=ultraiconversion(g)
coefficients(g::Vector,::Chebyshev,::Ultraspherical{1})=ultraconversion(g)
