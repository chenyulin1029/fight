#include "TestHarness.h"
#include "../runtime/FitUnderDialog.h"

#include <cmath>
#include <optional>
#include <string>

namespace {

void TestTargetMbParsing() {
    auto whole = filedone::ParseTargetMbText(L"10", L".");
    TEST_TRUE(whole.has_value());
    TEST_TRUE(std::fabs(*whole - 10.0) < 0.000001);

    auto invariant = filedone::ParseTargetMbText(L"1.5", L",");
    TEST_TRUE(invariant.has_value());
    TEST_TRUE(std::fabs(*invariant - 1.5) < 0.000001);

    auto local = filedone::ParseTargetMbText(L"1,5", L",");
    TEST_TRUE(local.has_value());
    TEST_TRUE(std::fabs(*local - 1.5) < 0.000001);

    auto trimmed = filedone::ParseTargetMbText(L"  2.25  ", L".");
    TEST_TRUE(trimmed.has_value());
    TEST_TRUE(std::fabs(*trimmed - 2.25) < 0.000001);

    TEST_FALSE(filedone::ParseTargetMbText(L"0", L".").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"-1", L".").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"nan", L".").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"inf", L".").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"10 MB", L".").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"1,2,3", L",").has_value());
    TEST_FALSE(filedone::ParseTargetMbText(L"", L".").has_value());
}

} // namespace

int main() {
    TestTargetMbParsing();
    return test::Finish();
}
