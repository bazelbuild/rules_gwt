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

  # Copy pubs to the war directory
  cmd = "rm -rf war\nmkdir war\ncp -LR %s war\n" % (
    " ".join([pub.path for pub in ctx.files.pubs]),
  )

  # Set up a working directory for dev mode
  cmd += "mkdir -p dev-workdir\n"

  # Determine the root directory of the package hierarchy. This needs to be on
  # the classpath for GWT to see changes to source files.
  cmd += "javaRoot=$(pwd | sed -e 's:\(.*\)%s.*:\\1:')../../../%s\n" % (ctx.attr.package_name, ctx.attr.java_root)
  cmd += 'echo "Dev mode working directoy is $(pwd)"\n'
  cmd += 'echo "Using Java sources rooted at $javaRoot"\n'
  cmd += 'if [ ! -d $javaRoot ]; then\n'
  cmd += '  echo "The Java root directory doesn\'t exist. Is java_root set correctly in your gwt_application?"\n'
  cmd += '  exit 1\n'
  cmd += 'fi\n'

  # Run dev mode
  cmd += "java %s -cp $javaRoot:%s com.google.gwt.dev.DevMode -war %s -workDir ./dev-workdir %s %s\n" % (
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
    "java_root": attr.string(mandatory=True),
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
    java_root="src/main/java",
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
    java_root: Directory relative to the workspace root that forms the root of the
      Java package hierarchy (e.g. it contains a `com` directory). By default this
      is src/main/java. If your Java files aren't under src/main/java, you must
      set this property in order for development mode to work correctly. Otherwise
      GWT won't be able to see your source files, so you will not see any changes
      reflected when refreshing dev mode.
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
    "//external:asm",
    "//external:javax-validation",
    "//external:javax-validation-src",
    "//external:gwt-dev",
    "//external:gwt-user",
  ]
  if len(srcs) > 0:
    native.java_binary(
      name = name + "-deps",
      resources = resources,
      srcs = srcs,
      deps = all_deps,
    )
  else:
    native.java_binary(
      name = name + "-deps",
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
    java_root = java_root,
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
    name = "asm_artifact",
    artifact = "org.ow2.asm:asm:5.0.3",
  )
  native.maven_jar(
    name = "gwt_dev_artifact",
    artifact = "com.google.gwt:gwt-dev:2.8.0-beta1",
  )
  native.maven_jar(
    name = "gwt_user_artifact",
    artifact = "com.google.gwt:gwt-user:2.8.0-beta1",
  )
  native.maven_jar(
    name = "javax_validation_artifact",
    artifact = "javax.validation:validation-api:1.0.0.GA",
  )
  native.http_jar(
    name = "javax_validation_sources_artifact",
    url = "http://repo1.maven.org/maven2/javax/validation/validation-api/1.0.0.GA/validation-api-1.0.0.GA-sources.jar",
 )

  native.bind(
    name = "asm",
    actual = "@asm_artifact//jar",
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
    name = "gwt-dev",
    actual = "@gwt_dev_artifact//jar",
  )
  native.bind(
    name = "gwt-user",
    actual = "@gwt_user_artifact//jar",
  )
