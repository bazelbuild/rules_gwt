"""GWT Rules

Skylark rules for building [GWT](http://www.gwtproject.org/) applications using
Bazel.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_jar")
load("@bazel_tools//tools/build_defs/repo:jvm.bzl", "jvm_maven_import_external")

def _gwt_war_impl(ctx):
    output_war = ctx.outputs.output_war
    output_dir = output_war.path + ".gwt_output"
    extra_dir = output_war.path + ".extra"

    # Find all transitive dependencies
    all_deps = _get_dep_jars(ctx)

    # Run the GWT compiler
    cmd = "%s %s -cp %s com.google.gwt.dev.Compiler -war %s -deploy %s -extra %s %s %s\n" % (
        ctx.executable._java.path,
        " ".join(ctx.attr.jvm_flags),
        ":".join([dep.path for dep in all_deps.to_list()]),
        output_dir + "/" + ctx.attr.output_root,
        output_dir + "/" + "WEB-INF/deploy",
        extra_dir,
        " ".join(ctx.attr.compiler_flags),
        " ".join(ctx.attr.modules),
    )

    # Copy pubs into the output war
    if len(ctx.files.pubs) > 0:
        cmd += "cp -LR %s %s\n" % (
            " ".join([pub.path for pub in ctx.files.pubs]),
            output_dir,
        )

    # Don't include the unit cache in the output
    cmd += "rm -rf %s/gwt-unitCache\n" % output_dir

    # Discover all of the generated files and write their paths to a file. Run the
    # paths through sed to trim out everything before the package root so that the
    # paths match how they should look in the war file.
    cmd += "find %s -type f | sed 's:^%s/::' > file_list\n" % (
        output_dir,
        output_dir,
    )

    # Create a war file using the discovered paths
    cmd += "root=`pwd`\n"
    cmd += "cd %s; $root/%s Cc ../%s @$root/file_list\n" % (
        output_dir,
        ctx.executable._zip.path,
        output_war.basename,
    )
    cmd += "cd $root\n"

    # Execute the command
    ctx.actions.run_shell(
        inputs = ctx.files.pubs + all_deps.to_list() + ctx.files._jdk,
        tools = ctx.files._zip,
        outputs = [output_war],
        mnemonic = "GwtCompile",
        progress_message = "GWT compiling " + output_war.short_path,
        command = "set -e\n" + cmd,
    )

_gwt_war = rule(
    implementation = _gwt_war_impl,
    attrs = {
        "deps": attr.label_list(allow_files = [".jar"]),
        "pubs": attr.label_list(allow_files = True),
        "modules": attr.string_list(mandatory = True),
        "output_root": attr.string(default = "."),
        "compiler_flags": attr.string_list(),
        "jvm_flags": attr.string_list(),
        "_java": attr.label(
            default = Label("@local_jdk//:bin/java"),
            executable = True,
            cfg = "host",
            allow_single_file = True,
        ),
        "_jdk": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        ),
        "_zip": attr.label(
            default = Label("@bazel_tools//tools/zip:zipper"),
            executable = True,
            cfg = "host",
            allow_single_file = True,
        ),
    },
    outputs = {
        "output_war": "%{name}.war",
    },
)

def _gwt_dev_impl(ctx):
    # Find all transitive dependencies that need to go on the classpath
    all_deps = _get_dep_jars(ctx)

    # TODO: to avoid flattening the depset, use ctx.actions.args
    dep_paths = [dep.short_path for dep in all_deps.to_list()]
    cmd = "#!/bin/bash\n\n"

    # Copy pubs to the war directory
    cmd += "rm -rf war\nmkdir war\ncp -LR %s war\n" % (
        " ".join([pub.path for pub in ctx.files.pubs]),
    )

    # Set up a working directory for dev mode
    cmd += "mkdir -p dev-workdir\n"

    # Determine the root directory of the package hierarchy. This needs to be on
    # the classpath for GWT to see changes to source files.
    cmd += 'echo "Dev mode working directoy is $(pwd)"\n'
    cmd += 'javaRoots=("%s")\n' % '" "'.join(ctx.attr.java_roots)
    cmd += "srcClasspath=''\n"
    cmd += "for root in ${javaRoots[@]}; do\n"
    cmd += "  rootDir=$(pwd | sed -e 's:\\(.*\\)%s.*:\\1:')../../../$root\n" % (ctx.attr.package_name)
    cmd += "  if [ -d $rootDir ]; then\n"
    cmd += "    srcClasspath+=:$rootDir\n"
    cmd += '    echo "Using Java sources rooted at $rootDir"\n'
    cmd += "  else\n"
    cmd += '    echo "No Java sources found under $rootDir"\n'
    cmd += "  fi\n"
    cmd += "done\n"

    # Run dev mode
    cmd += "java %s -cp $srcClasspath:%s com.google.gwt.dev.DevMode -war %s -workDir ./dev-workdir %s %s\n" % (
        " ".join(ctx.attr.jvm_flags),
        ":".join(dep_paths),
        "war/" + ctx.attr.output_root,
        " ".join(ctx.attr.dev_flags),
        " ".join(ctx.attr.modules),
    )

    # Return the script and all dependencies needed to run it
    ctx.actions.write(
        output = ctx.outputs.executable,
        content = cmd,
    )
    return struct(
        executable = ctx.outputs.executable,
        runfiles = ctx.runfiles(files = all_deps.to_list() + ctx.files.pubs),
    )

_gwt_dev = rule(
    implementation = _gwt_dev_impl,
    attrs = {
        "package_name": attr.string(mandatory = True),
        "java_roots": attr.string_list(mandatory = True),
        "deps": attr.label_list(mandatory = True, allow_files = [".jar"]),
        "modules": attr.string_list(mandatory = True),
        "pubs": attr.label_list(allow_files = True),
        "output_root": attr.string(default = "."),
        "dev_flags": attr.string_list(),
        "jvm_flags": attr.string_list(),
    },
    executable = True,
)

def _get_dep_jars(ctx):
    all_deps = depset(ctx.files.deps)
    for this_dep in ctx.attr.deps:
        if hasattr(this_dep, "java"):
            all_deps += this_dep.java.transitive_runtime_deps
            all_deps += this_dep.java.transitive_source_jars
    return all_deps

def gwt_application(
        name,
        srcs = [],
        resources = [],
        modules = [],
        pubs = [],
        deps = [],
        visibility = [],
        output_root = ".",
        java_roots = ["java", "javatests", "src/main/java", "src/test/java"],
        compiler_flags = [],
        compiler_jvm_flags = [],
        dev_flags = [],
        dev_jvm_flags = []):
    """Builds a .war file and a development mode target for a GWT application.

    This rule runs the GWT compiler to generate <name>.war, which will contain all
    output generated by the compiler as well as the files specified in pubs. It
    also defines the <name>-war implicit output target, which can be executed via
    bazel run to launch the app in development mode.

    Args:
      name: A unique name for this rule.
      srcs: List of .java source files that will be compiled and passed on the
        classpath to the GWT compiler.
      resources: List of resource files that will be passed on the classpath to the
        GWT compiler, e.g. .gwt.xml, .ui.xml, and .css files.
      modules: List of fully-qualified names of modules that will be passed to the
        GWT compiler. Usually contains a single module name corresponding to the
        application's .gwt.xml file.
      pubs: Files that will be copied directly to the output war, such as static
        HTML or image resources. Not interpretted by the GWT compiler.
      deps: List of other java_libraries on which the application depends. Both the
        class jars and the source jars corresponding to each library as well as
        their transitive dependencies will be passed to the GWT compiler's
        classpath. These libraries may contain other .gwt.xml, .ui.xml, etc. files
        as resources.
      visibility: The visibility of this rule.
      output_root: Directory in the output war in which all outputs will be placed.
        By default outputs are placed at the root of the war file.
      java_roots: Directories relative to the workspace root that form roots of the
        Java package hierarchy (e.g. they contain `com` directories). By default
        this includes "java", "javatests", "src/main/java" and "src/test/java". If
        your Java files aren't under these directories, you must set this property
        in order for development mode to work correctly. Otherwise GWT won't be
        able to see your source files, so you will not see any changes reflected
        when refreshing dev mode.
      compiler_flags: Additional flags that will be passed to the GWT compiler.
      compiler_jvm_flags: Additional JVM flags that will be passed to the GWT
        compiler, such as `-Xmx4G` to increase the amount of available memory.
      dev_flags: Additional flags that will be passed to development mode.
      dev_jvm_flags: Additional JVM flags that will be passed to development mode,
        such as `-Xmx4G` to increase the amount of available memory.
    """

    # Create a dummy java_binary to generate a deploy jar containing all transtive
    # deps and srcs. We have to do this instead of passing the transitive jars on
    # th classpath directly, since in large projects the classpath length could
    # exceed the maximum command-line length accepted by the OS.
    all_deps = deps + [
        "//external:gwt-dev",
        "//external:gwt-user",
        "//external:gwt_ant",
        "//external:gwt_asm",
        "//external:gwt_colt",
        "//external:gwt_commons-io",
        "//external:gwt_gson",
        "//external:gwt_javax-servlet",
        "//external:gwt_javax-validation",
        "//external:gwt_javax-validation-src",
        "//external:gwt_jetty-annotations",
        "//external:gwt_jetty-http",
        "//external:gwt_jetty-io",
        "//external:gwt_jetty-jndi",
        "//external:gwt_jetty-plus",
        "//external:gwt_jetty-security",
        "//external:gwt_jetty-server",
        "//external:gwt_jetty-servlet",
        "//external:gwt_jetty-servlets",
        "//external:gwt_jetty-util",
        "//external:gwt_jetty-webapp",
        "//external:gwt_jetty-xml",
        "//external:gwt_jsinterop",
        "//external:gwt_jsinterop-src",
        "//external:gwt_jsr-250-api",
        "//external:gwt_sac",
        "//external:gwt_tapestry",
    ]
    if len(srcs) > 0:
        native.java_binary(
            name = name + "-deps",
            main_class = name,
            resources = resources,
            srcs = srcs,
            deps = all_deps,
        )
    else:
        native.java_binary(
            name = name + "-deps",
            main_class = name,
            resources = resources,
            runtime_deps = all_deps,
        )

    # Create the war and dev mode targets
    _gwt_war(
        name = name,
        output_root = output_root,
        deps = [
            name + "-deps_deploy.jar",
            name + "-deps_deploy-src.jar",
        ],
        modules = modules,
        visibility = visibility,
        pubs = pubs,
        compiler_flags = compiler_flags,
        jvm_flags = compiler_jvm_flags,
    )
    _gwt_dev(
        name = name + "-dev",
        java_roots = java_roots,
        output_root = output_root,
        package_name = native.package_name(),
        deps = [
            name + "-deps_deploy.jar",
            name + "-deps_deploy-src.jar",
        ],
        modules = modules,
        visibility = visibility,
        pubs = pubs,
        dev_flags = dev_flags,
        jvm_flags = dev_jvm_flags,
    )

def gwt_repositories():
    jvm_maven_import_external(
        name = "gwt_ant_artifact",
        artifact = "org.apache.ant:ant:1.9.7",
        artifact_sha256 = "9a5dbe3f5f2cb91854c8682cab80178afa412ab35a5ab718bf39ce01b3435d93",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_asm_artifact",
        artifact = "org.ow2.asm:asm:5.0.3",
        artifact_sha256 = "71c4f78e437b8fdcd9cc0dfd2abea8c089eb677005a6a5cff320206cc52b46cc",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # BSD License
    )
    jvm_maven_import_external(
        name = "gwt_colt_artifact",
        artifact = "colt:colt:1.2.0",
        artifact_sha256 = "e1fcbfbdd0d0caedadfb59febace5a62812db3b9425f3a03ef4c4cbba3ed0ee3",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["unencumbered"], # No License 
    )
    jvm_maven_import_external(
        name = "gwt_commons_io_artifact",
        artifact = "commons-io:commons-io:2.4",
        artifact_sha256 = "cc6a41dc3eaacc9e440a6bd0d2890b20d36b4ee408fe2d67122f328bb6e01581",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_dev_artifact",
        artifact = "com.google.gwt:gwt-dev:2.9.0",
        artifact_sha256 = "55f9b79b4f66aad63301f7b99166db827fa5f677a7d8673138bad078eb1bd706",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["unencumbered"], # No License  
    )
    jvm_maven_import_external(
        name = "gwt_gson_artifact",
        artifact = "com.google.code.gson:gson:2.6.2",
        artifact_sha256 = "b8545ba775f641f8bba86027f06307152279fee89a46a4006df1bf2f874d4d9d",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License        
    )
    jvm_maven_import_external(
        name = "gwt_javax_servlet_artifact",
        artifact = "javax.servlet:javax.servlet-api:3.1.0",
        artifact_sha256 = "af456b2dd41c4e82cf54f3e743bc678973d9fe35bd4d3071fa05c7e5333b8482",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["reciprocal"], # CDDL License
    )
    jvm_maven_import_external(
        name = "gwt_javax_validation_artifact",
        artifact = "javax.validation:validation-api:1.0.0.GA",
        artifact_sha256 = "e459f313ebc6db2483f8ceaad39af07086361b474fa92e40f442e8de5d9895dc",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    http_jar(
        name = "gwt_javax_validation_sources_artifact",
        url = "https://repo1.maven.org/maven2/javax/validation/validation-api/1.0.0.GA/validation-api-1.0.0.GA-sources.jar",
        sha256 = "a394d52a9b7fe2bb14f0718d2b3c8308ffe8f37e911956012398d55c9f9f9b54",
    )
    jvm_maven_import_external(
        name = "gwt_jetty_annotations_artifact",
        artifact = "org.eclipse.jetty:jetty-annotations:9.2.14.v20151106",
        artifact_sha256 = "d2e7774a3a15d6169d728c7f42b0e2b8a6dd3ed77dc776a2352e7a5b9b5f3a6b",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_http_artifact",
        artifact = "org.eclipse.jetty:jetty-http:9.2.14.v20151106",
        artifact_sha256 = "635e5912cb14dfaefdf8fc7369fe96baa8d888b691a00290603d8bda41b80d61",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_io_artifact",
        artifact = "org.eclipse.jetty:jetty-io:9.2.14.v20151106",
        artifact_sha256 = "16f2d49f497e5e42c92d96618adee2626af5ba1ac927589529b6fd9a92266d3a",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_jndi_artifact",
        artifact = "org.eclipse.jetty:jetty-jndi:9.2.14.v20151106",
        artifact_sha256 = "9181d263612c457437d6f7e8470588eed862cdf1f08eec808d6577503bec5653",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_plus_artifact",
        artifact = "org.eclipse.jetty:jetty-plus:9.2.14.v20151106",
        artifact_sha256 = "6c2c574507c693ad76fde1500b9090baccf346313ed342d98c4104234149bdf8",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_security_artifact",
        artifact = "org.eclipse.jetty:jetty-security:9.2.14.v20151106",
        artifact_sha256 = "1810b2395f6f0717aef296c6c2d6f9504deb2076ef68b3312e1644c0b9cc3921",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_server_artifact",
        artifact = "org.eclipse.jetty:jetty-server:9.2.14.v20151106",
        artifact_sha256 = "bedeec57bccd1680c8ec71ea0071d4e6946fd8152668b69ab753b34729993e8b",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_servlet_artifact",
        artifact = "org.eclipse.jetty:jetty-servlet:9.2.14.v20151106",
        artifact_sha256 = "ac13cca38e1541647a2fbe726a871dc5c22a757c0d8900c08d77302e414a725f",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_servlets_artifact",
        artifact = "org.eclipse.jetty:jetty-servlets:9.2.14.v20151106",
        artifact_sha256 = "2a6e50cc48cfb5de3c3cf15176e229861ac7bc5e03285408078658298b75c421",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_util_artifact",
        artifact = "org.eclipse.jetty:jetty-util:9.2.14.v20151106",
        artifact_sha256 = "277a2cc734139f620bf5c88c09af2f0328b0114f6fad52776abfbcd8d37166ce",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_webapp_artifact",
        artifact = "org.eclipse.jetty:jetty-webapp:9.2.14.v20151106",
        artifact_sha256 = "1865f0d3c0edc8727eb4e4d1f9c808cec039095e95cfff45816ea6f7059e6fc5",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jetty_xml_artifact",
        artifact = "org.eclipse.jetty:jetty-xml:9.2.14.v20151106",
        artifact_sha256 = "3d13667a02e331c86b124d020338ec5cc901a7986ddf9fd99782578fe77a0459",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # Apache 2.0 License
    )
    jvm_maven_import_external(
        name = "gwt_jsinterop_artifact",
        artifact = "com.google.jsinterop:jsinterop-annotations:1.0.0",
        artifact_sha256 = "e5c1e0ceef98fb65a3d382641bcc1faab97649da1b422bbfc60e21b47345c854",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["unencumbered"], # No License
    )
    http_jar(
        name = "gwt_jsinterop_sources_artifact",
        url = "https://repo1.maven.org/maven2/com/google/jsinterop/jsinterop-annotations/1.0.0/jsinterop-annotations-1.0.0-sources.jar",
        sha256 = "80d63c117736ae2fb9837b7a39576f3f0c5bd19cd75127886550c77b4c478f87",
    )
    jvm_maven_import_external(
        name = "gwt_jsr_250_api_artifact",
        artifact = "javax.annotation:jsr250-api:1.0",
        artifact_sha256 = "a1a922d0d9b6d183ed3800dfac01d1e1eb159f0e8c6f94736931c1def54a941f",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["reciprocal"], # CDDL License
    )
    jvm_maven_import_external(
        name = "gwt_sac_artifact",
        artifact = "org.w3c.css:sac:1.3",
        artifact_sha256 = "003785669f921aafe4f137468dd20a01a36111e94fd7449f26c16e7924d82d23",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["notice"], # W3C License
    )
    jvm_maven_import_external(
        name = "gwt_tapestry_artifact",
        artifact = "tapestry:tapestry:4.0.2",
        artifact_sha256 = "16dfc5b6b322bb0734b80e89d77fbeb987c809002fe59d52d9707a035949b107",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["unencumbered"], # No License
    )
    jvm_maven_import_external(
        name = "gwt_user_artifact",
        artifact = "com.google.gwt:gwt-user:2.9.0",
        artifact_sha256 = "80420ddfb3b7e2aedc29222328d34a8ebd9f8abab63a82ddf9d837d06a68f7fe",
        server_urls = ["https://repo1.maven.org/maven2"],
        licenses = ["unencumbered"], # No License
    )

    native.bind(
        name = "gwt-dev",
        actual = "@gwt_dev_artifact//jar",
    )
    native.bind(
        name = "gwt-user",
        actual = "@gwt_user_artifact//jar",
    )
    native.bind(
        name = "gwt_ant",
        actual = "@gwt_ant_artifact//jar",
    )
    native.bind(
        name = "gwt_asm",
        actual = "@gwt_asm_artifact//jar",
    )
    native.bind(
        name = "gwt_colt",
        actual = "@gwt_colt_artifact//jar",
    )
    native.bind(
        name = "gwt_commons-io",
        actual = "@gwt_commons_io_artifact//jar",
    )
    native.bind(
        name = "gwt_gson",
        actual = "@gwt_gson_artifact//jar",
    )
    native.bind(
        name = "gwt_javax-servlet",
        actual = "@gwt_javax_servlet_artifact//jar",
    )
    native.bind(
        name = "gwt_javax-validation",
        actual = "@gwt_javax_validation_artifact//jar",
    )
    native.bind(
        name = "gwt_javax-validation-src",
        actual = "@gwt_javax_validation_sources_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-annotations",
        actual = "@gwt_jetty_annotations_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-http",
        actual = "@gwt_jetty_http_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-io",
        actual = "@gwt_jetty_io_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-jndi",
        actual = "@gwt_jetty_jndi_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-plus",
        actual = "@gwt_jetty_plus_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-security",
        actual = "@gwt_jetty_security_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-server",
        actual = "@gwt_jetty_server_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-servlet",
        actual = "@gwt_jetty_servlet_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-servlets",
        actual = "@gwt_jetty_servlets_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-util",
        actual = "@gwt_jetty_util_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-webapp",
        actual = "@gwt_jetty_webapp_artifact//jar",
    )
    native.bind(
        name = "gwt_jetty-xml",
        actual = "@gwt_jetty_xml_artifact//jar",
    )
    native.bind(
        name = "gwt_jsinterop",
        actual = "@gwt_jsinterop_artifact//jar",
    )
    native.bind(
        name = "gwt_jsinterop-src",
        actual = "@gwt_jsinterop_sources_artifact//jar",
    )
    native.bind(
        name = "gwt_jsr-250-api",
        actual = "@gwt_jsr_250_api_artifact//jar",
    )
    native.bind(
        name = "gwt_sac",
        actual = "@gwt_sac_artifact//jar",
    )
    native.bind(
        name = "gwt_tapestry",
        actual = "@gwt_tapestry_artifact//jar",
    )
