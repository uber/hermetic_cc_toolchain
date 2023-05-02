// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

#include <iostream>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " path/to/hello_world_binary" << std::endl;
        return 1;
    }

    std::string command = argv[1];
    int result = std::system(command.c_str());

    if (result == 0) {
        std::cout << "Hello, World! test passed." << std::endl;
    } else {
        std::cerr << "Hello, World! test failed. Return code: " << result << std::endl;
        return 1;
    }

    return 0;
}
