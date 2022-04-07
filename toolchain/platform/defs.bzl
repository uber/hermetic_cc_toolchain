def declare_platforms():
    # create @zig_sdk//{os}_{arch}_platform entries with zig and go conventions
    for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64")):
        for bzlos, oss in {"linux": ["linux"], "macos": ["macos", "darwin"]}.items():
            for os in oss:
                constraint_values = [
                    "@platforms//os:{}".format(bzlos),
                    "@platforms//cpu:{}".format(zigcpu),
                ]
                native.platform(
                    name = "{os}_{zigcpu}".format(os = os, zigcpu = zigcpu),
                    constraint_values = constraint_values,
                )
                native.platform(
                    name = "{os}_{gocpu}".format(os = os, gocpu = gocpu),
                    constraint_values = constraint_values,
                )
