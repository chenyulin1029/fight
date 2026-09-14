#pragma once
#include <iostream>
#include <string>

namespace test {
inline int failures = 0;
inline void Fail(const char* expr, const char* file, int line) {
    ++failures;
    std::cerr << file << ":" << line << " FAIL: " << expr << "\n";
}
template <class A, class B>
inline void Equal(const A& a, const B& b, const char* expr, const char* file, int line) {
    if (!(a == b)) Fail(expr, file, line);
}
inline int Finish() {
    if (failures == 0) std::cout << "PASS\n";
    else std::cout << "FAILURES=" << failures << "\n";
    return failures == 0 ? 0 : 1;
}
}
#define TEST_EQ(a,b) ::test::Equal((a),(b),#a " == " #b,__FILE__,__LINE__)
#define TEST_TRUE(x) do { if(!(x)) ::test::Fail(#x,__FILE__,__LINE__); } while(0)
#define TEST_FALSE(x) TEST_TRUE(!(x))
