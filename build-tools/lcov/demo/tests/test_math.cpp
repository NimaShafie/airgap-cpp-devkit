#include "../src/math.h"
#include <cassert>
#include <iostream>

int main() {
    assert(add(2, 3) == 5);
    assert(add(-1, 1) == 0);
    assert(subtract(10, 4) == 6);
    assert(multiply(3, 4) == 12);
    // divide() intentionally NOT called — shows as uncovered in report
    std::cout << "All tests passed.\n";
    return 0;
}
