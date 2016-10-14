"""GWT Rules

Skylark rules for building [GWT](http://www.gwtproject.org/) applications using
Bazel.
"""

def _gwt_war_impl(ctx):
  output_war = ctx.outputs.output_war
  output_dir = output_war.path + ".gwt_output"
  extra_dir = output_war.path + ".extra"

  # Find all transitive dependencies
  all_deps = _get_dep_jars(ctx)

  # Run the GWT compiler
  cmd = "external/local_jdk/bin/java %s -cp %s com.google.gwt.dev.Compiler -war %s -deploy %s -extra %s %s %s\n" % (
    " ".join(ctx.attr.jvm_flags),
    ":".join([dep.path for dep in all_deps]),
    output_dir + "/" + ctx.attr.output_root,
    output_dir + "/" + "WEB-INF/deploy",
    extra_dir,
    " ".join(ctx.attr.compiler_flags),
    " ".join(ctx.attr.modules),
  )

  # Copy pubs into the output war
  if len(ctx.files.pubs) > 0:
    cmd += "cp -r %s %s\n" % (
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
  ctx.action(
    inputs = ctx.files.pubs + list(all_deps) + ctx.files._jdk + ctx.files._zip,
    outputs = [output_war],
    mnemonic = "GwtCompile",
    progress_message = "GWT compiling " + output_war.short_path,
    command = "set -e\n" + cmd,
  )

_gwt_war = rule(
  implementation = _gwt_war_impl,
  attrs = {
    "deps": attr.label_list(allow_files=FileType([".jar"])),
    "pubs": attr.label_list(allow_files=True),
    "modules": attr.string_list(mandatory=True),
    "output_root": attr.string(default="."),
    "compiler_flags": attr.string_list(),
    "jvm_flags": attr.string_list(),
    "_jdk": attr.label(
      default=Label("//tools/defaults:jdk")),
    "_zip": attr.label(
      default=Label("@bazel_tools//tools/zip:zipper"),
      executable=True,
      single_file=True),
  },
  outputs = {
    "output_war": "%{name}.war",
  },
)

def _gwt_dev_impl(ctx):
  # Find all transitive dependencies that need to go on the classpath
  all_deps = _get_dep_jars(ctx)
  dep_paths = [dep.short_path for dep in all_deps]
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
  cmd += "  rootDir=$(pwd | sed -e 's:\(.*\)%s.*:\\1:')../../../$root\n" % (ctx.attr.package_name)
  cmd += '  if [ -d $rootDir ]; then\n'
  cmd += "    srcClasspath+=:$rootDir\n"
  cmd += '    echo "Using Java sources rooted at $rootDir"\n'
  cmd += '  else\n'
  cmd += '    echo "No Java sources found under $rootDir"\n'
  cmd += '  fi\n'
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
  ctx.file_action(
    output = ctx.outputs.executable,
    content = cmd,
  )
  return struct(
    executable = ctx.outputs.executable,
    runfiles = ctx.runfiles(files = list(all_deps) + ctx.files.pubs),
  )

_gwt_dev = rule(
  implementation = _gwt_dev_impl,
  attrs = {
    "package_name": attr.string(mandatory=True),
    "java_roots": attr.string_list(mandatory=True),
    "deps": attr.label_list(mandatory=True, allow_files=FileType([".jar"])),
    "modules": attr.string_list(mandatory=True),
    "pubs": attr.label_list(allow_files=True),
    "output_root": attr.string(default="."),
    "dev_flags": attr.string_list(),
    "jvm_flags": attr.string_list(),
  },
  executable = True,
)

def _get_dep_jars(ctx):
  all_deps = set(ctx.files.deps)
  for this_dep in ctx.attr.deps:
    if hasattr(this_dep, 'java'):
      all_deps += this_dep.java.transitive_runtime_deps
      all_deps += this_dep.java.transitive_source_jars
  return all_deps

def gwt_application(
    name,
    srcs=[],
    resources=[],
    modules=[],
    pubs=[],
    deps=[],
    visibility=[],
    output_root=".",
    java_roots=["java", "javatests", "src/main/java", "src/test/java"],
    compiler_flags=[],
    compiler_jvm_flags=[],
    dev_flags=[],
    dev_jvm_flags=[]):
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
    "//external:ant",
    "//external:asm",
    "//external:colt",
    "//external:commons-io",
    "//external:gwt-dev",
    "//external:gwt-user",
    "//external:javax-servlet",
    "//external:javax-validation",
    "//external:javax-validation-src",
    "//external:jetty-annotations",
    "//external:jetty-http",
    "//external:jetty-io",
    "//external:jetty-jndi",
    "//external:jetty-plus",
    "//external:jetty-security",
    "//external:jetty-server",
    "//external:jetty-servlet",
    "//external:jetty-servlets",
    "//external:jetty-util",
    "//external:jetty-webapp",
    "//external:jetty-xml",
    "//external:jsinterop",
    "//external:jsinterop-src",
    "//external:jsr-250-api",
    "//external:sac",
    "//external:tapestry",
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
    package_name = PACKAGE_NAME,
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
  native.maven_jar(
    name = "ant_artifact",
    artifact = "org.apache.ant:ant:1.9.7",
    sha1 = "3b2a10512ee6537d3852c9b693a0284dcab5de68",
  )
  native.maven_jar(
    name = "asm_artifact",
    artifact = "org.ow2.asm:asm:5.0.3",
    sha1 = "dcc2193db20e19e1feca8b1240dbbc4e190824fa",
  )
  native.maven_jar(
    name = "colt_artifact",
    artifact = "colt:colt:1.2.0",
    sha1 = "0abc984f3adc760684d49e0f11ddf167ba516d4f",
  )
  native.maven_jar(
    name = "commons_io_artifact",
    artifact = "commons-io:commons-io:2.4",
    sha1="b1b6ea3b7e4aa4f492509a4952029cd8e48019ad",
  )
  native.maven_jar(
    name = "gwt_dev_artifact",
    artifact = "com.google.gwt:gwt-dev:2.8.0-rc3",
    sha1 = "af7b628b0b9a8b475d438f0a53ca7a5bd27d88f8",
  )
  native.maven_jar(
    name = "gwt_user_artifact",
    artifact = "com.google.gwt:gwt-user:2.8.0-rc3",
    sha1 = "3195c357eda0477a8ed91762a3e4b8320d2096a7",
  )
  native.maven_jar(
    name = "javax_servlet_artifact",
    artifact = "javax.servlet:javax.servlet-api:3.1.0",
    sha1 = "3cd63d075497751784b2fa84be59432f4905bf7c",
  )
  native.maven_jar(
    name = "javax_validation_artifact",
    artifact = "javax.validation:validation-api:1.0.0.GA",
    sha1 = "b6bd7f9d78f6fdaa3c37dae18a4bd298915f328e",
  )
  native.http_jar(
    name = "javax_validation_sources_artifact",
    url = "http://repo1.maven.org/maven2/javax/validation/validation-api/1.0.0.GA/validation-api-1.0.0.GA-sources.jar",
    sha256 = "a394d52a9b7fe2bb14f0718d2b3c8308ffe8f37e911956012398d55c9f9f9b54",
  )
  native.maven_jar(
    name = "jetty_annotations_artifact",
    artifact = "org.eclipse.jetty:jetty-annotations:9.2.14.v20151106",
    sha1 = "bb7030e5d13eaf9023f38e297c8b2fcae4f8be9b",
  )
  native.maven_jar(
    name = "jetty_http_artifact",
    artifact = "org.eclipse.jetty:jetty-http:9.2.14.v20151106",
    sha1 = "699ad1f2fa6fb0717e1b308a8c9e1b8c69d81ef6",
  )
  native.maven_jar(
    name = "jetty_io_artifact",
    artifact = "org.eclipse.jetty:jetty-io:9.2.14.v20151106",
    sha1 = "dfa4137371a3f08769820138ca1a2184dacda267",
  )
  native.maven_jar(
    name = "jetty_jndi_artifact",
    artifact = "org.eclipse.jetty:jetty-jndi:9.2.14.v20151106",
    sha1 = "c5fb5420a99b8aee335a3ff804c6094eb9034d04",
  )
  native.maven_jar(
    name = "jetty_plus_artifact",
    artifact = "org.eclipse.jetty:jetty-plus:9.2.14.v20151106",
    sha1 = "1e9304873f2d3563d814a1e714add6b6b3ac0b24",
  )
  native.maven_jar(
    name = "jetty_security_artifact",
    artifact = "org.eclipse.jetty:jetty-security:9.2.14.v20151106",
    sha1 = "2d36974323fcb31e54745c1527b996990835db67",
  )
  native.maven_jar(
    name = "jetty_server_artifact",
    artifact = "org.eclipse.jetty:jetty-server:9.2.14.v20151106",
    sha1 = "70b22c1353e884accf6300093362b25993dac0f5",
  )
  native.maven_jar(
    name = "jetty_servlet_artifact",
    artifact = "org.eclipse.jetty:jetty-servlet:9.2.14.v20151106",
    sha1 = "3a2cd4d8351a38c5d60e0eee010fee11d87483ef",
  )
  native.maven_jar(
    name = "jetty_servlets_artifact",
    artifact = "org.eclipse.jetty:jetty-servlets:9.2.14.v20151106",
    sha1 = "a75c78a0ee544073457ca5ee9db20fdc6ed55225",
  )
  native.maven_jar(
    name = "jetty_util_artifact",
    artifact = "org.eclipse.jetty:jetty-util:9.2.14.v20151106",
    sha1 = "0057e00b912ae0c35859ac81594a996007706a0b",
  )
  native.maven_jar(
    name = "jetty_webapp_artifact",
    artifact = "org.eclipse.jetty:jetty-webapp:9.2.14.v20151106",
    sha1 = "773f1c45f6534bff6313997ab3bdbe25533ee255",
  )
  native.maven_jar(
    name = "jetty_xml_artifact",
    artifact = "org.eclipse.jetty:jetty-xml:9.2.14.v20151106",
    sha1 = "946a5a1d4fb816fd346dba74d09a6c0e162cafcd",
  )
  native.maven_jar(
    name = "jsinterop_artifact",
    artifact = "com.google.jsinterop:jsinterop-annotations:1.0.0",
    sha1 = "23c3a3c060ffe4817e67673cc8294e154b0a4a95",
  )
  native.http_jar(
    name = "jsinterop_sources_artifact",
    url = "http://central.maven.org/maven2/com/google/jsinterop/jsinterop-annotations/1.0.0/jsinterop-annotations-1.0.0-sources.jar",
    sha256 = "80d63c117736ae2fb9837b7a39576f3f0c5bd19cd75127886550c77b4c478f87",
  )
  native.maven_jar(
    name = "jsr_250_api_artifact",
    artifact = "javax.annotation:jsr250-api:1.0",
    sha1 = "5025422767732a1ab45d93abfea846513d742dcf",
  )
  native.maven_jar(
    name = "sac_artifact",
    artifact = "org.w3c.css:sac:1.3",
    sha1="cdb2dcb4e22b83d6b32b93095f644c3462739e82",
  )
  native.maven_jar(
    name = "tapestry_artifact",
    artifact = "tapestry:tapestry:4.0.2",
    sha1 = "e855a807425d522e958cbce8697f21e9d679b1f7",
  )

  native.bind(
    name = "ant",
    actual = "@ant_artifact//jar",
  )
  native.bind(
    name = "asm",
    actual = "@asm_artifact//jar",
  )
  native.bind(
    name = "colt",
    actual = "@colt_artifact//jar",
  )
  native.bind(
    name = "commons-io",
    actual = "@commons_io_artifact//jar",
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
    name = "javax-servlet",
    actual = "@javax_servlet_artifact//jar",
  )
  native.bind(
    name = "javax-validation",
    actual = "@javax_validation_artifact//jar",
  )
  native.bind(
    name = "javax-validation-src",
    actual = "@javax_validation_sources_artifact//jar",
  )
  native.bind(
    name = "jetty-annotations",
    actual = "@jetty_annotations_artifact//jar",
  )
  native.bind(
    name = "jetty-http",
    actual = "@jetty_http_artifact//jar",
  )
  native.bind(
    name = "jetty-io",
    actual = "@jetty_io_artifact//jar",
  )
  native.bind(
    name = "jetty-jndi",
    actual = "@jetty_jndi_artifact//jar",
  )
  native.bind(
    name = "jetty-plus",
    actual = "@jetty_plus_artifact//jar",
  )
  native.bind(
    name = "jetty-security",
    actual = "@jetty_security_artifact//jar",
  )
  native.bind(
    name = "jetty-server",
    actual = "@jetty_server_artifact//jar",
  )
  native.bind(
    name = "jetty-servlet",
    actual = "@jetty_servlet_artifact//jar",
  )
  native.bind(
    name = "jetty-servlets",
    actual = "@jetty_servlets_artifact//jar",
  )
  native.bind(
    name = "jetty-util",
    actual = "@jetty_util_artifact//jar",
  )
  native.bind(
    name = "jetty-webapp",
    actual = "@jetty_webapp_artifact//jar",
  )
  native.bind(
    name = "jetty-xml",
    actual = "@jetty_xml_artifact//jar",
  )
  native.bind(
    name = "jsinterop",
    actual = "@jsinterop_artifact//jar",
  )
  native.bind(
    name = "jsinterop-src",
    actual = "@jsinterop_sources_artifact//jar",
  )
  native.bind(
    name = "jsr-250-api",
    actual = "@jsr_250_api_artifact//jar",
  )
  native.bind(
    name = "sac",
    actual = "@sac_artifact//jar",
  )
  native.bind(
    name = "tapestry",
    actual = "@tapestry_artifact//jar",
  )
