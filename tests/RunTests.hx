import tink.testrunner.*;
import tink.unit.*;
import tink.unit.Assert.assert;
import sys.FileSystem;
using tink.CoreApi;
using Lambda;

class RunTests {
    #if !macro
    static function main() {
        Runner.run(TestBatch.make([
            new TestBuild()
        ])).handle(Runner.exit);
    }
    #end
    static function run() {
        anvil.Anvil.run();
    }
}
#if !macro
class TestBuild{
    var asserts:AssertionBuffer = new AssertionBuffer();
    public function new() {}
    public function simple_test_build() {
        anvil.Anvil.run();
        
        final pathsToCheck = [
            './native_extensions/odbc',
            './native_extensions/odbc/odbc.c',
            './native_extensions/odbc/odbc.h',
            './native_extensions/odbc/Makefile.msvc',
            './native_extensions/odbc/odbc.dll',
            './native_extensions/odbc/odbc.exp',
            './native_extensions/odbc/odbc.lib',
            './bin/odbc.dll'
        ].map(FileSystem.fullPath);
        for(path in pathsToCheck){
            asserts.assert(FileSystem.exists(path) == true);
        }
        asserts.done();
        return asserts;
    }
}#end