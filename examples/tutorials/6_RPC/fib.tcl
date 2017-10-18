
proc fib {n} {
    if {$n == 0} {
        return 0
    } elseif {$n == 1} {
        return 1
    } else {
        set arg1 [expr {$n - 1}]
        set arg2 [expr {$n - 2}]
        return [expr {[fib $arg1] + [fib $arg2]}]
    }
}
