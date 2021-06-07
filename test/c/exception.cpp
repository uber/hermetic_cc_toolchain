#include <iostream>

int main() {
  std::cerr << "will throw and expect to catch an error..." << std::endl;

  try {
    throw "error";
  } catch (const char* msg) {
    std::cerr << "caught: " << msg << std::endl;
  }
  std::cerr << "done" << std::endl;
}
