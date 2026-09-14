#include "TestHarness.h"
#include "../runtime/RuntimeTypes.h"

int main() {
    TEST_EQ(filedone::ParseActionToken(L"compatible"), filedone::Action::Compatible);
    return test::Finish();
}
