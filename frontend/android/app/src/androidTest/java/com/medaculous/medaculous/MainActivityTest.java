package com.medaculous.medaculous;

// Required glue between Android's JUnit test discovery and Patrol's Dart-side
// tests (patrol_test/) — Patrol's own docs don't ship this via a CLI bootstrap
// command in this version, so it's copied from the pattern in Patrol's own
// example app (leancodepl/patrol, packages/patrol/example/android/.../MainActivityTest.java).
// Without this, PatrolJUnitRunner has no JUnit @Test methods to discover and
// `patrol test` silently reports 0 tests run.
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import org.junit.runners.Parameterized.Parameters;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(Parameterized.class)
public class MainActivityTest {
    @Parameters(name = "{0}")
    public static Object[] testCases() {
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        return instrumentation.listDartTests();
    }

    public MainActivityTest(String dartTestName) {
        this.dartTestName = dartTestName;
    }

    private final String dartTestName;

    @Test
    public void runDartTest() {
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.runDartTest(dartTestName);
    }
}
