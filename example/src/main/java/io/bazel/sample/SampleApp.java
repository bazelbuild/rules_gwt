package io.bazel.sample;

import com.google.gwt.core.client.EntryPoint;
import io.bazel.sample.lib.Greeter;

/**
 * A simple app that displays "Hello world" in an alert when the page loads.
 */
public class SampleApp implements EntryPoint {
  @Override
  public void onModuleLoad() {
    Greeter.greet();
  }
}
