load("@bazel_gazelle//:deps.bzl", "go_repository")

def go_repositories():
    go_repository(
        name = "com_github_datadog_zstd",
        importpath = "github.com/DataDog/zstd",
        sum = "h1:Rpmta4xZ/MgZnriKNd24iZMhGpP5dvUcs/uqfBapKZY=",
        version = "v1.4.8",
    )
    go_repository(
        name = "com_github_mattn_go_sqlite3",
        importpath = "github.com/mattn/go-sqlite3",
        sum = "h1:10HX2Td0ocZpYEjhilsuo6WWtUqttj2Kb0KtD86/KYA=",
        version = "v1.14.9",
    )
