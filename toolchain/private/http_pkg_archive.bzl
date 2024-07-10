load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "get_auth",
    "patch",
    "workspace_and_buildfile",
)

# From https://github.com/uber/hermetic_cc_toolchain/issues/10#issuecomment-2045684532
def http_pkg_archive_impl(rctx):
    rctx.download(
        url = rctx.attr.urls,
        output = ".downloaded.pkg",
        sha256 = rctx.attr.sha256,
        canonical_id = " ".join(rctx.attr.urls),
        auth = get_auth(rctx, rctx.attr.urls),
    )

    res = rctx.execute(["/usr/sbin/pkgutil", "--expand-full", ".downloaded.pkg", "tmp"])
    if res.return_code != 0:
        fail("Failed to extract package: {}".format(res.stdout))
    rctx.delete(".downloaded.pkg")

    strip_prefix = "tmp/Payload/"
    if rctx.attr.strip_prefix:
        strip_prefix += rctx.attr.strip_prefix + "/"
    extracted = rctx.path(strip_prefix)
    if not extracted.is_dir or not extracted.exists:
        fail("Extracted package does not contain expected directory: {}".format(strip_prefix))
    entries = extracted.readdir(watch = "no")
    for entry in entries:
        rctx.execute(["mv", str(entry), entry.basename])
    rctx.delete(extracted)
    patch(rctx)

http_pkg_archive = repository_rule(
    http_pkg_archive_impl,
    attrs = {
        "urls": attr.string_list(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(),
        "workspace_file": attr.label(allow_single_file = True),
        "workspace_file_content": attr.string(),
    },
)