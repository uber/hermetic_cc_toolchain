#!/usr/bin/awk -f

BEGIN {stage=0};

!/```/ && stage==0 {
    print
}

/```/ && stage==0 {
    print "```"
    print "BAZEL_ZIG_CC_VERSION = \""tag"\""
    print ""
    print "http_archive("
    print "    name = \"bazel-zig-cc\","
    print "    sha256 = \""sha256sum"\","
    print "    strip_prefix = \"bazel-zig-cc-{}\".format(BAZEL_ZIG_CC_VERSION),"
    print "    urls = [\"https://git.sr.ht/~motiejus/bazel-zig-cc/archive/{}.tar.gz\".format(BAZEL_ZIG_CC_VERSION)],"
    print ")"
    stage=1
    next
}

!/^)$/ && stage==1 {
    next
};

/^)$/ && stage==1 {
    stage=2
    next
};

stage==2 {
    print;
};
