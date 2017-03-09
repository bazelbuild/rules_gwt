# GWT Rules for Bazel

<div class="toc">
  <h2>Rules</h2>
  <ul>
    <li><a href="#gwt_application">gwt_application</a></li>
  </ul>
</div>

## Overview

These build rules are used for building [GWT](http://www.gwtproject.org/)
applications with Bazel. Applications are compiled as `.war` files containing
compiled JavaScript and other resources. GWT applications can also be run in
[Development Mode](http://www.gwtproject.org/doc/latest/DevGuideCompilingAndDebugging.html)
via `bazel run`.

<a name="setup"></a>
## Setup

To be able to use the GWT rules, you must provide bindings for the GWT jars and
everything it depends on. The easiest way to do so is to add the following to
your `WORKSPACE` file, which will give you default versions for GWT and each
dependency:

```python
http_archive(
  name = "io_bazel_rules_gwt",
  url = "https://github.com/bazelbuild/rules_gwt/archive/0.1.1.tar.gz",
  sha256 = "9d467196576448a315110fe8eb5b04ed2aa5e2d67bc2f5822da1dbabb3a92e92",
  strip_prefix = "rules_gwt-0.1.1",
)
load("@io_bazel_rules_gwt//gwt:gwt.bzl", "gwt_repositories")
gwt_repositories()
```

If you want to use a different version of GWT or any of its dependencies, you
must provide your own bindings. Remove the `gwt_repositories()` line above and
add a `bind` rule for each of the following in your `WORKSPACE`:

  * `//external:gwt-dev` (defaults to [`com.google.gwt:gwt-dev:2.8.0`](https://mvnrepository.com/artifact/com.google.gwt/gwt-dev/2.8.0))
  * `//external:gwt-user` (defaults to [`com.google.gwt:gwt-user:2.8.0`](https://mvnrepository.com/artifact/com.google.gwt/gwt-user/2.8.0))
  * `//external:gwt_ant` (defaults to [`org.apache.ant:ant:1.9.7`](https://mvnrepository.com/artifact/org.apache.ant/ant/1.9.7))
  * `//external:gwt_asm` (defaults to [`org.ow2.asm:asm:5.0.3`](https://mvnrepository.com/artifact/org.ow2.asm/asm/5.0.3))
  * `//external:gwt_colt` (defaults to [`colt:colt:1.2.0`](https://mvnrepository.com/artifact/colt/colt/1.2.0))
  * `//external:gwt_commons-io` (defaults to [`commons-io:commons-io:2.4`](https://mvnrepository.com/artifact/commons-io/commons-io/2.4))
  * `//external:gwt_gson` (defaults to [`com.google.code.gson:gson:2.6.2`](https://mvnrepository.com/artifact/com.google.code.gson/gson/2.6.2))
  * `//external:gwt_javax-servlet` (defaults to [`javax.servlet:javax.servlet-api:3.1.0`](https://mvnrepository.com/artifact/javax.servlet/javax.servlet-api/3.1.0))
  * `//external:gwt_javax-validation` (defaults to [`javax.validation:validation-api:1.0.0.GA`](https://mvnrepository.com/artifact/javax.validation/validation-api/1.0.0.GA))
  * `//external:gwt_java-validation-src` (defaults to [`javax.validation:validation-api:sources:1.0.0.GA`](https://mvnrepository.com/artifact/javax.validation/validation-api/1.0.0.GA))
  * `//external:gwt_jetty-annotations` (defaults to [`org.eclipse.jetty:jetty-annotations:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-annotations/9.2.14.v20151106))
  * `//external:gwt_jetty-http` (defaults to [`org.eclipse.jetty:jetty-http:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-http/9.2.14.v20151106))
  * `//external:gwt_jetty-io` (defaults to [`org.eclipse.jetty:jetty-io:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-io/9.2.14.v20151106))
  * `//external:gwt_jetty-jndi` (defaults to [`org.eclipse.jetty:jetty-jndi:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-jndi/9.2.14.v20151106))
  * `//external:gwt_jetty-plus` (defaults to [`org.eclipse.jetty:jetty-plus:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-plus/9.2.14.v20151106))
  * `//external:gwt_jetty-security` (defaults to [`org.eclipse.jetty:jetty-security:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-security/9.2.14.v20151106))
  * `//external:gwt_jetty-server` (defaults to [`org.eclipse.jetty:jetty-server:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-server/9.2.14.v20151106))
  * `//external:gwt_jetty-servlet` (defaults to [`org.eclipse.jetty:jetty-servlet:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-servlet/9.2.14.v20151106))
  * `//external:gwt_jetty-servlets` (defaults to [`org.eclipse.jetty:jetty-servlets:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-servlets/9.2.14.v20151106))
  * `//external:gwt_jetty-util` (defaults to [`org.eclipse.jetty:jetty-util:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-util/9.2.14.v20151106))
  * `//external:gwt_jetty-webapp` (defaults to [`org.eclipse.jetty:jetty-io:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-webapp/9.2.14.v20151106))
  * `//external:gwt_jetty-xml` (defaults to [`org.eclipse.jetty:jetty-io:9.2.14.v20151106`](https://mvnrepository.com/artifact/org.eclipse.jetty/jetty-xml/9.2.14.v20151106))
  * `//external:gwt_jsinterop` (defaults to [`com.google.jsinterop:jsinterop-annotations:1.0.0`](https://mvnrepository.com/artifact/com.google.jsinterop/jsinterop-annotations/1.0.0))
  * `//external:gwt_jsinterop-src` (defaults to [`com.google.jsinterop:jsinterop-annotations:sources:1.0.0`](https://mvnrepository.com/artifact/com.google.jsinterop/jsinterop-annotations/1.0.0))
  * `//external:gwt_jsr-250-api` (defaults to [`javax.annotation:jsr250-api:1.0`](https://mvnrepository.com/artifact/javax.annotation/jsr250-api/1.0))
  * `//external:gwt_sac` (defaults to [`org.w3c.css:sac:1.3`](https://mvnrepository.com/artifact/org.w3c.css/sac/1.3))
  * `//external:gwt_tapestry` (defaults to [`tapestry:tapestry:4.0.2`](https://mvnrepository.com/artifact/tapestry/tapestry/4.0.2))

<a name="basic-example"></a>
## Basic Example

Suppose you have the following directory structure for a simple GWT application:

```
[workspace]/
    WORKSPACE
    src/main/java/
        app/
            BUILD
            MyApp.java
            MyApp.gwt.xml
        lib/
            BUILD
            MyLib.java
        public/
            index.html
```

Here, `MyApp.java` defines the entry point to a GWT application specified by
`MyApp.gwt.xml` which depends on another Java library `MyLib.java`. `index.html`
defines the HTML page that links in the GWT application. To build this app, your
`src/main/java/app/BUILD` can look like this:

```python
load("@io_bazel_rules_gwt//gwt:gwt.bzl", "gwt_application")

gwt_application(
  name = "MyApp",
  srcs = glob(["*.java"]),
  resources = glob(["*.gwt.xml"]),
  modules = ["app.MyApp"],
  pubs = glob(["public/*"]),
  deps = [
    "//src/main/java/lib",
  ],
)
```

Now, you can build the GWT application by running
`bazel build src/main/java/app:MyApp`. This will run the GWT compiler and place
all of its output as well as `index.html` into
`bazel-bin/src/main/java/app/MyApp.war`. You can also run
`bazel run src/main/java/app:MyApp-dev` to run GWT development mode for the
application. Once development mode has started, you can see the app by opening
http://127.0.0.1:8888/index.html in a browser. Note that development mode assumes
that all of your `.java` files are located under `java/` or `src/main/java/` - see
details on the `java_roots` flag below if this is not the case.

For a complete example, see the
[`example/`](https://github.com/bazelbuild/rules_gwt/tree/master/example/src/main/java/io/bazel/sample)
directory in this repository.

<a name="gwt_application"></a>
## gwt_application

```python
gwt_application(name, srcs, resources, modules, pubs, deps, output_root, java_root, compiler_flags, compiler_jvm_flags, dev_flags, dev_jvm_flags):
```

### Implicit output targets

 * `<name>.war`: archive containing GWT compiler output and any files passed
   in via pubs.
 * `<name>-dev`: script that can be run via `bazel run` to launch the app in
   development mode.

<table class="table table-condensed table-bordered table-params">
  <colgroup>
    <col class="col-param" />
    <col class="param-description" />
  </colgroup>
  <thead>
    <tr>
      <th colspan="2">Attributes</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>name</code></td>
      <td>
        <code>Name, required</code>
        <p>A unique name for this rule.</p>
      </td>
    </tr>
    <tr>
      <td><code>srcs</code></td>
      <td>
        <code>List of labels, optional</code>
        <p>
          List of .java source files that will be compiled and passed on the
          classpath to the GWT compiler.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>resources</code></td>
      <td>
        <code>List of labels, optional</code>
        <p>
          List of resource files that will be passed on the classpath to the GWT
          compiler, e.g. <code>.gwt.xml</code>, <code>.ui.xml</code>, and
          <code>.css</code> files.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>modules</code></td>
      <td>
        <code>List of strings, required</code>
        <p>
          List of fully-qualified names of modules that will be passed to the GWT
          compiler. Usually contains a single module name corresponding to the
          application's <code>.gwt.xml</code> file.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>pubs</code></td>
      <td>
        <code>List of labels, optional</code>
        <p>
          Files that will be copied directly to the output war, such as static
          HTML or image resources. Not interpreted by the GWT compiler.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>deps</code></td>
      <td>
        <code>List of labels, optional</code>
        <p>
          List of other java_libraries on which the application depends. Both the
          class jars and the source jars corresponding to each library as well as
          their transitive dependencies will be passed to the GWT compiler's
          classpath. These libraries may contain other <code>.gwt.xml</code>,
          <code>.ui.xml</code>, etc. files as <code>resources</code>.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>output_root</code></td>
      <td>
        <code>String, optional</code>
        <p>
          Directory in the output war in which all outputs will be placed. By
          default outputs are placed at the root of the war file.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>java_roots</code></td>
      <td>
        <code>List of strings, optional</code>
        <p>
          Directories relative to the workspace root that form roots of the
          Java package hierarchy (e.g. they contain <code>com</code> directories).
          By default this includes <code>java</code>, <code>javatests</code>,
          <code>src/main/java</code> and <code>src/test/java</code>. If your Java
          files aren't under these directories, you must set this property in order
          for development mode to work correctly. Otherwise GWT won't be able to
          see your source files, so you will not see any changes reflected when
          refreshing dev mode.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>compiler_flags</code></td>
      <td>
        <code>List of strings, optional</code>
        <p>
          Additional flags that will be passed to the GWT compiler. See
          <a href='http://www.gwtproject.org/doc/latest/DevGuideCompilingAndDebugging.html#DevGuideCompilerOptions'>here</a>
          for a list of available flags.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>compiler_jvm_flags</code></td>
      <td>
        <code>List of strings, optional</code>
        <p>
          Additional JVM flags that will be passed to the GWT compiler, such as
          <code>-Xmx4G</code> to increase the amount of available memory.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>dev_flags</code></td>
      <td>
        <code>List of strings, optional</code>
        <p>
          Additional flags that will be passed to development mode. See
          <a href='http://www.gwtproject.org/doc/latest/DevGuideCompilingAndDebugging.html#What_options_can_be_passed_to_development_mode'>here</a>
          for a list of available flags.
        </p>
      </td>
    </tr>
    <tr>
      <td><code>dev_jvm_flags</code></td>
      <td>
        <code>List of strings, optional</code>
        <p>
          Additional JVM flags that will be passed to development mode, such as
          <code>-Xmx4G</code> to increase the amount of available memory.
        </p>
      </td>
    </tr>
  </tbody>
</table>
