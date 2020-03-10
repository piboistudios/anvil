import tink.testrunner.*;
import tink.unit.*;
import tink.unit.Assert.assert;
#if !hxnodejs
import sys.FileSystem;
#end

using tink.CoreApi;
using Lambda;

class RunTests {
	#if (!macro)
	static function main() {
		Runner.run(TestBatch.make([new TestBuild()])).handle(Runner.exit);
	}
	#end

	static function prerun() {
		var hxMakeCompiler = #if eval haxe.macro.Context.definedValue('hxmake-compiler') #else "gcc" #end;
		if (hxMakeCompiler == null)
			hxMakeCompiler = 'gcc';
		#if macro
		haxe.macro.Compiler.define('hxmake_$hxMakeCompiler');
		#end
	}
}

#if !macro
class TestBuild {
	var asserts:AssertionBuffer = new AssertionBuffer();

	public function new() {}

	// function changeCompiler(compiler:String) {
	// 	#if eval
	// 	haxe.macro.Compiler.define('hxmake-compiler',compiler);
	// 	#end
	// }
	public function simple_test_build() {
		// final compilers = ['cl','gcc','clang'];
		// for(compiler in compilers) {
		anvil.Anvil.run();
		final nativeLibs = ['odbc'];
		for (lib in nativeLibs) {
			final pathsToCheck = [
				'./native_extensions/$lib',
				'./native_extensions/$lib/odbc.c',
				'./native_extensions/$lib/odbc.h',
				'./native_extensions/$lib/HxMakefile.test',
				'./native_extensions/$lib/$lib.dll',
				#if hxmake_cl './native_extensions/$lib/$lib.exp', './native_extensions/$lib/$lib.lib', './native_extensions/$lib/$lib.obj',
				#end
				'./bin/$lib.dll'
			].map(FileSystem.fullPath);

			for (path in pathsToCheck) {
				asserts.assert(FileSystem.exists(path) == true);
			}
		}
		// }
		asserts.done();
		return asserts;
	}
}
#end
