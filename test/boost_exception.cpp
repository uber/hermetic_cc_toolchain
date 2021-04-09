#include <iostream>

#include <boost/lexical_cast.hpp>

int main() {
  std::cout << "about to cast \"1\" to double!" << std::endl;
  std::cout << boost::lexical_cast<double>("1") << std::endl;

  std::cout << "about to cast \"z\" to double, but expecting to catch bad_lexical_cast" << std::endl;
  try {
    std::cout << boost::lexical_cast<double>("z");
    std::cout << "uh-oh, should have thrown an exception before here." << std::endl;
  } catch (const boost::bad_lexical_cast &e) {
    std::cout << "caught bad_lexical_cast" << std::endl;
  }

  std::cout << "about to cast \"z\" to double, should see an uncaught exception." << std::endl;
  std::cout << boost::lexical_cast<double>("z");
  std::cout << "uh-oh, should have thrown an exception before here." << std::endl;
}
