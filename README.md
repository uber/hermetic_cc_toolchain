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
