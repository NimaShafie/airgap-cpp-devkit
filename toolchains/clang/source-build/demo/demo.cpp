// demo/demo.cpp
// Author: Nima Shafie
//
// Intentionally contains issues that clang-tidy will flag.
// Run with: bash demo/run-demo.sh
//
// Expected diagnostics (non-exhaustive):
//   - modernize-use-nullptr           : use of NULL macro instead of nullptr
//   - modernize-use-override          : missing 'override' on virtual method
//   - modernize-loop-convert          : index-based loop convertible to range-for
//   - readability-magic-numbers       : bare numeric literal as function arg
//   - cppcoreguidelines-init-variables: uninitialized local variable
//   - performance-unnecessary-copy-initialization: copy of std::string param

#include <iostream>
#include <string>
#include <vector>

// --- Issue: missing 'override' on virtual method ---
struct Base {
    virtual void process(int value) { (void)value; }
    virtual ~Base() = default;
};

struct Derived : public Base {
    void process(int value) {   // should be: void process(int value) override
        (void)value;
    }
};

// --- Issue: use of NULL instead of nullptr ---
void check_pointer() {
    int* p = NULL;              // should be: int* p = nullptr;
    if (p == NULL) {            // should be: if (p == nullptr)
        std::cout << "null\n";
    }
}

// --- Issue: uninitialized local variable ---
void uninitialized_demo() {
    int x;                      // never assigned before use
    std::cout << x << "\n";     // undefined behavior
}

// --- Issue: index-based loop convertible to range-for ---
void loop_demo(const std::vector<int>& items) {
    for (std::size_t i = 0; i < items.size(); ++i) {   // prefer range-for
        std::cout << items[i] << "\n";
    }
}

// --- Issue: unnecessary copy of string parameter ---
void print_label(std::string label) {           // should be const std::string&
    std::cout << label << "\n";
}

// --- Issue: magic number passed directly to function ---
void magic_numbers_demo() {
    std::vector<int> v;
    v.reserve(42);              // 42 is a magic number — name it
}

int main() {
    Derived d;
    d.process(1);

    check_pointer();
    uninitialized_demo();

    std::vector<int> nums = {1, 2, 3};
    loop_demo(nums);
    print_label("demo");
    magic_numbers_demo();

    return 0;
}