load("//gwt:gwt.bzl", "gwt_application")

# Use gwt_application to define your app. It will generate two targets: you can
# run `bazel build` on `SampleApp` to create a .war file containing the compiled
# application, or you can run `bazel run` on `SampleApp-dev` to run development
# mode for your application.
gwt_application(
    # Name of the build target. Required.
    name = "SampleApp",

    # Source files to include when running the GWT compiler. A jar is created
    # with these files (along with any specified by resources) and included on
    # the classpath during compilation. These are optional here, you don't need
    # to include them if all the sources you need exist in other deps.
    srcs = glob(["*.java"]),

    # Optional flags to pass to the GWT compiler and to dev mode. See
    # http://www.gwtproject.org/doc/latest/DevGuideCompilingAndDebugging.html for
    # more details.
    compiler_flags = [
        "-strict",
        "-sourceLevel 1.8",
    ],
    compiler_jvm_flags = [
        "-Xmx1G",
    ],
    dev_flags = [
        "-logLevel DEBUG",
    ],
    dev_jvm_flags = [
        "-Xmx1G",
    ],

    # The root of the Java package hierarchy (which usually contains a top-level
    # package like "com"), relative to the root of the workspace (the directory
    # containing the WORKSPACE file). By default, this is set to "src/main/java".
    # If your java files aren't under src/main/java (which is the case in this
    # example), you must set this attribute for dev mode to function correctly.
    java_root = "example/src/main/java",

    # Name of the GWT modules to be compiled, which should correspond to .gwt.xml
    # files. At least one is required.
    modules = ["io.bazel.sample.SampleApp"],

    # Files that should be copied directly into the output war, like a static html
    # page that bootstraps the GWT app. Optional.
    pubs = glob(["public/*"]),

    # Resources to include on the classpath when running the GWT compiler. Make
    # sure to include your .gwt.xml file and any other resources (e.g. css or
    # .ui.xml files). These are optional and don't need to be included here if
    # the files you need exist in other deps.
    resources = glob(["*.gwt.xml"]),

    # java_libraries that will be included on the classpath when running the GWT
    # compiler. Can contain java classes and resource files.
    deps = [
        "//example/src/main/java/io/bazel/sample/lib",
    ],
)
