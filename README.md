To run the example locally, first make sure `bazelisk` is on your PATH. Then

Test that things work at all:

```
$ bazelisk run //test:hello
...
Hello World!
```

Then test that you can run docker images:
```
$ bazelisk run //test:hello_image
...
Hello World!
```

Now we can check if C++ exceptions work locally:
```
$ bazelisk run //test:exception
...
will throw and expect to catch an error...
caught: error
done
```

And whether or not they work in a docker container:
```
$ bazelisk run //test:exception_image
```

If they *work*, then you'll see the same output as above. If not, you'll see:

```
will throw and expect to catch an error...
libc++abi: terminating with uncaught exception of type char const*
```

If you want to try the above in a transient docker environment, you can do:

```
$ docker run --rm -it -v $(pwd):/workspace debian:buster-slim
# apt update && apt install curl ca-certificates --no-install-recommends -y && curl -L https://github.com/bazelbuild/bazelisk/releases/download/v1.7.5/bazelisk-linux-amd64 > /usr/bin/bazel && chmod +x /usr/bin/bazel
# cd /workspace
# export CC=/usr/bin/false
# bazel run --platforms=@com_github_ziglang_zig//:x86_64-linux-gnu.2.28 //test:hello
# bazel run --platforms=@com_github_ziglang_zig//:x86_64-linux-gnu.2.28 //test:exception
```