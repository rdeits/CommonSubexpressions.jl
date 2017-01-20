using Base.Test
using CombinedSubexpressions

@testset "basic usage" begin
    f_count = 0
    function f(x)
        f_count += 1
        1
    end

    g_count = 0
    function g(x)
        g_count += 1
        2
    end

    @test f_count == 0
    @test g_count == 0

    x = 1
    @cse [f(g(x)) for i in 1:10]
    @test f_count == 1
    @test g_count == 1

    f_count = 0
    g_count = 0
    [f(g(x)) for i in 1:10]
    @test f_count == 10
    @test g_count == 10

    h_count = 0
    function h(x, y)
        h_count += 1
        3
    end

    @cse function foo(x)
        [h(h(f(g(x)), g(x)), i) == i for i in 1:5]
    end
    f_count = 0
    g_count = 0
    h_count = 0
    @test foo(1) == [false, false, true, false, false]
    @test f_count == 1
    @test g_count == 1
    @test h_count == 6
end
