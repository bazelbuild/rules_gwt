package io.bazel.sample.lib;

import com.google.gwt.user.client.Window;

/**
 * An external linrary that the main GWT application depends on.
 */
public class Greeter {
  public static void greet() {
    Window.alert("Hello world!");
  }
}
