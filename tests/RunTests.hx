import tink.testrunner.*;
import tink.unit.*;
import tink.unit.Assert.assert;
import sys.FileSystem;

using tink.CoreApi;
using Lambda;

class RunTests {
	#if !macro
	static function main() {
		Runner.run(TestBatch.make([new TestBuild()])).handle(Runner.exit);
	}
	#end

	static function run() {
		anvil.Anvil.run();
	}
}

#if !macro
class TestBuild {
	var asserts:AssertionBuffer = new AssertionBuffer();

	public function new() {}

	public function simple_test_build() {
		anvil.Anvil.run();
		final nativeLibs = ['odbc', 'odbc-alt'];
		for (lib in nativeLibs) {
			final pathsToCheck = [
				'./native_extensions/$lib',
				'./native_extensions/$lib/odbc.c',
				'./native_extensions/$lib/odbc.h',
				'./native_extensions/$lib/Makefile.msvc',
				'./native_extensions/$lib/Makefile.alt.msvc',
				'./native_extensions/$lib/$lib.dll',
				'./native_extensions/$lib/odbc.exp',
				'./native_extensions/$lib/odbc.lib',
				'./bin/$lib.dll'
			].map(FileSystem.fullPath);

			for (path in pathsToCheck) {
				asserts.assert(FileSystem.exists(path) == true);
			}
		}
		asserts.done();
		return asserts;
	}
}
#end
