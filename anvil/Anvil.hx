package anvil;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

using Lambda;

import sys.io.File;
import sys.FileSystem;
import haxe.PosInfos;

using haxe.io.Path;
#if macro
using haxe.macro.PositionTools;
#end

enum abstract DeployType(String)  from String to String {
	var WithUserOutput = 'with-user-output';
	var ToPath = 'to-path';
}

typedef AnvilConfig = {
	var ?windows:Array<AnvilPlatformConfig>;
	var ?linux:Array<AnvilPlatformConfig>;
	var ?bsd:Array<AnvilPlatformConfig>;
	var ?mac:Array<AnvilPlatformConfig>;
}

typedef AnvilPlatformConfig = {
	var ammerLib:String; // e.g. what you used to define -D ammer.lib.<ammerLib>.library etc...
	var nativePath:String; // the path to the native code from the root of your project
	var ?hxMakefile:String; // ** NEW ** build your project using an HxMakefile; this assumes the user has HxMake.exe in their PATH
	var ?buildCmd:String; // the build command to run (this will run with the native path as its working directory; ensure all environment variables are set in order for this command to be successful)

	var ?outputBinaries:Array<String>; // list of binaries that need to be processed; if this isn't provided, anvil will infer what binaries to move
	// if anvil infers this, it will assume that if any library binary exists, the project was already fully built
	// otherwise it will compare the directory contents to the outputBinaries to determine if the project is already built
	//  when determining whether or not to skip compilation
	// i.e. If using MSVC toolchain, vsdevcmd.bat/vsvars32.bat need to be run in the shell before this.
	var ?buildArgs:Array<String>; // arguments for the build command. This works like Sys.command or new sys.io.Process, can be omitted (with args in cmd name)
	var ?verbose:Bool; // pipes the stdout of the build command to the stdout of the haxe build command.
	var ?libPath:String; // where the binaries are, if not at nativePath
	var ?includePath:String; // where the headers are if not at nativePath
	var ?deployInfo:{
		var type:DeployType; // with-user-output or to-path
		var ?dest:String; // if to-path, the destination path to put built binaries
	};
	var ?cacheMode:CacheMode; // cache mode, either always, on-change, or never.
			// on-change will rebuild whenever the source files are changed
					// this is the default setting
}

enum abstract CacheMode(String) from String to String {
	var OnChange = 'on-change';
	var Never = 'never';
	var Always = 'always';
}
typedef BuildResults = {
	var libs:Array<Path>; // list of dynamic library binaries/object files
}

class Anvil {
	static var runningDirectory:Path;
	static var haxelibPath = Sys.getEnv('HAXELIB_PATH');
	static var pos:PosInfos;
	static var lastBuild:Date;
	static var endl = Sys.systemName() == 'Windows' ? '\r\n' : '\n';
	static var LAST_BUILD_FILE = './anvil.lastbuild.txt';
	public static function run(?p:haxe.PosInfos) {
		pos = p;
		runningDirectory = new Path(Sys.getCwd());
		if(sys.FileSystem.exists(LAST_BUILD_FILE)) {
			try {

				lastBuild = Date.fromString(sys.io.File.getContent(LAST_BUILD_FILE));
			} catch(ex:Dynamic) {
				#if macro
				Context.warning('Unable to read last build time. Will rebuild. (Error: $ex)', macroPos());
				#end
			}
		}
		sys.io.File.saveContent(LAST_BUILD_FILE, Date.now().toString());
		if(FileSystem.exists('./.gitignore'))
			if(sys.io.File.getContent('./.gitignore').indexOf(LAST_BUILD_FILE) == -1) {
				var appender = sys.io.File.append('./.gitignore', false);
				appender.writeString('$endl$LAST_BUILD_FILE$endl');
				appender.flush();
				appender.close();
			}
		if (!init())
			return;
		for (c in configs) {
			config = c;
			getNativeLibraryDirectory();
			getTargetDirectory();
			copyNativeToTargetDirectory();
			var results = buildTargetDirectory();
			config.deployInfo = config.deployInfo != null ? config.deployInfo : {type: WithUserOutput};
			switch config.deployInfo.type {
				case WithUserOutput:
					deployAsDependency(results);
				case ToPath:
					deployToDirectory(results);
			}
		}
		Sys.setCwd(runningDirectory.toString());
		haxe.Log.trace = _trace;
	}

	static var nativeLibraryDirectory:Path;
	static var platform = Sys.systemName().toLowerCase();
	static var configs:Array<AnvilPlatformConfig>;

	#if macro
	static inline function macroPos() {
		return PositionTools.make({file: config == null ? 'anvil-$platform' : 'anvil-$platform-${config.ammerLib}', max: 0, min: 0});
	}
	#end

	static final _trace = haxe.Log.trace;

	static function init() {
		haxe.Log.trace = (msg, ?pos:haxe.PosInfos) -> {
			if(config.verbose) {

				#if (macro)
				Context.info(msg, macroPos());
				#else
				_trace(msg, pos);
				#end
			}
			return;
		};
		getConfigs();
		if (configs == null) {
			trace('Unable to find anvil configuration for the desired platform. $platform.');
			trace('Aborting');
			return false;
		}

		return true;
	}

	static var config:AnvilPlatformConfig;
	static var basePath:Path;

	static function getConfigs() {
		final thisPath = new haxe.io.Path(FileSystem.fullPath(pos.fileName));
		basePath = new haxe.io.Path(FileSystem.fullPath('${thisPath.dir}'));
		while (!getAnvilConfigs(basePath)) {
			basePath = new Path(FileSystem.fullPath('${basePath.dir}'));
		}
	}

	static function getNativeLibraryDirectory() {
		nativeLibraryDirectory = new Path(haxe.io.Path.join([basePath.toString(), config.nativePath]));
	}

	static function getAnvilConfigs(basePath:Path) {
		var configPath = '$basePath\\.anvilrc';
		if (!FileSystem.exists(configPath)) {
			return false;
		}
		final globalConfig:haxe.DynamicAccess<Dynamic> = haxe.Json.parse(sys.io.File.getContent(configPath));
		configs = globalConfig[platform];
		if (configs == null)
			configs = globalConfig['all'];
		if (configs == null)
			return true;
		return true;
	}

	static var targetDirectory:Path;

	static function getTargetDirectory() {
		targetDirectory = new Path(Path.join([runningDirectory.toString(), 'native_extensions', config.ammerLib]));
	}

	static function copyFile(file:Path, dest:Path) {
		File.saveBytes(dest.toString(), File.getBytes(file.toString()));
	}

	static function copyDirectory(dir:Path, dest:Path) {
		if (dir == null || dest == null)
			return;
		if (!FileSystem.exists(dest.toString())) {
			FileSystem.createDirectory(dest.toString());
		}
		for (item in FileSystem.readDirectory(dir.toString())) {
			final fullItemPath = new Path(Path.join([dir.toString(), item]));
			final fullDestPath = new Path(Path.join([dest.toString(), item]));
			if (FileSystem.isDirectory(item)) {
				copyDirectory(fullItemPath, fullDestPath);
			} else {
				copyFile(fullItemPath, fullDestPath);
			}
		}
	}

	static function copyNativeToTargetDirectory() {
		copyDirectory(nativeLibraryDirectory, targetDirectory);
		#if macro
		var ammerIncludeDefine = 'ammer.lib.${config.ammerLib}.include';
		var ammerLibraryDefine = 'ammer.lib.${config.ammerLib}.library';
		Compiler.define(ammerIncludeDefine, Path.join([targetDirectory.toString(), config.includePath]));
		Compiler.define(ammerLibraryDefine, Path.join([targetDirectory.toString(), config.libPath]));
		#end
	}
	
	static function getSourceFiles() {
		final ret = [];
		inline function addFile(path, file) ret.push(FileSystem.fullPath(Path.join([path, file])));
		for(file in FileSystem.readDirectory('$nativeLibraryDirectory')) {
			addFile('$nativeLibraryDirectory', file);
		}
		if(config.includePath != null && config.includePath.length != 0) {
			final nativeIncludes = Path.join(['$nativeLibraryDirectory', config.includePath]);
			for(file in FileSystem.readDirectory(nativeIncludes)) {
				addFile(nativeIncludes, file);
			}
		}
		return ret;
	}
	static function sourcesWereChanged() {
		final ret = lastBuild == null || !getSourceFiles().foreach(file -> {
			final stat = sys.FileSystem.stat(file);
			return stat.mtime.getTime() < lastBuild.getTime();
		});
		if(ret) trace('A change was detected; rebuilding');
		return ret;
	}
	static var targetOutputDirectory:Path;

	static function willSkipBuild(state:BuildResults) {
		final ret = (switch config.cacheMode {
			case Never: true;
			case OnChange: !sourcesWereChanged();
			case Always: false;
			default: !sourcesWereChanged();
		}) && 
		(config.outputBinaries == null 
			|| config.outputBinaries.length == 0) 
			? 
				state.libs.length != 0 : 
				config.outputBinaries != null && config.outputBinaries.foreach(bin ->
					state.libs.exists((lib:Path) -> lib.file.withExtension(lib.ext)
						.toLowerCase() == bin.toLowerCase()
					)
				);
		return ret;
	}

	static function runCmd(cmd:String, args:Array<String>, ?verbose:Bool):Void {
		function newProcess(c, a) {
			return new sys.io.Process(c, a).exitCode(true);
		};
		(verbose ? Sys.command : newProcess)(cmd, args);
	}

	static function runBuild() {
		if (config.buildCmd != null)
			if (config.verbose #if eval || true #end)
				Sys.command(config.buildCmd, config.buildArgs);
			else
				new sys.io.Process(config.buildCmd, config.buildArgs).exitCode(true);
		else if (config.hxMakefile != null) {
			var hxMakeCompiler = #if eval haxe.macro.Context.definedValue('hxmake-compiler') #else Sys.systemName().toLowerCase() == 'windows' ? 'cl' ? 'gcc' #end;
			if (hxMakeCompiler == null)
				hxMakeCompiler = 'cl';
			#if macro
			Compiler.define(~/[,-.\s]/gi.replace('hxmake_$hxMakeCompiler', '_'));
			#end
			final lixLibCache = Sys.getEnv('HAXE_LIBCACHE');
			final useLix = lixLibCache != null && lixLibCache.length != 0;
			final verbose = config.verbose ? '-v' : '';
			var cmd = "";
			var args = [];
			if (useLix) {
				cmd = 'lix';
				args = ['run', 'hxmake', config.hxMakefile, hxMakeCompiler, verbose];
			} else {
				cmd = 'haxelib';
				args = ['run', 'hxmake', config.hxMakefile, hxMakeCompiler, verbose];
			}
			
				if (config.verbose #if eval || true #end) 
					Sys.command(cmd, args);
				else
					new sys.io.Process(cmd, args).exitCode(true);
		
		}
	}

	static function buildTargetDirectory() {
		targetOutputDirectory = new Path(Path.join([targetDirectory.toString(), config.libPath]));
		final initialState = getBuildResults();
		if (#if macro !Context.defined('--force-anvil') && #end willSkipBuild(initialState)) {
			trace('Skipping build for ${config.ammerLib}');
			return {libs: []};
		}
		Sys.setCwd(targetDirectory.toString());
		runBuild();

		if (!FileSystem.exists(targetDirectory.toString()))
			FileSystem.createDirectory(targetDirectory.toString());

		if (!FileSystem.exists(targetOutputDirectory.toString()))
			FileSystem.createDirectory(targetOutputDirectory.toString());
		return getBuildResults();
	}

	static var libExtensions:Array<String> = ['dll', 'dylib', 'so'];

	static function getBuildResults():BuildResults {
		return {
			libs: targetOutputDirectory == null ? [] : FileSystem.readDirectory(targetOutputDirectory.toString())
				.map(file -> new Path(FileSystem.fullPath(Path.join([targetOutputDirectory.toString(), file]))))
				.filter(fp -> libExtensions.indexOf(fp.ext) != -1)}
	}

	static var warnedAboutOutput = false;

	static function deployAsDependency(results:BuildResults) {
		var outputDir = "bin";
		#if macro
		if (!Context.defined('anvil.output')) {
			final platform = Context.defined('hl') ? 'hl' : Context.defined('lua') ? 'lua' : Context.defined('cpp') ? 'cpp' : '';
			outputDir = 'bin\\$platform';
			if (config.verbose && !warnedAboutOutput) {
				warnedAboutOutput = true;
				Context.warning('-D anvil.output flag missing, outputting to default folder: ${Path.join([runningDirectory.toString(), outputDir])}',
					macroPos());
			}
		} else {
			outputDir = Context.definedValue('anvil.output');
		}
		#else
		// if()
		#end

		var fullOutputDir = Path.join([runningDirectory.toString(), outputDir]);
		if (!FileSystem.exists(fullOutputDir))
			FileSystem.createDirectory(fullOutputDir);
		copyLibsToPath(results, fullOutputDir);
	}

	static function deployToDirectory(results:BuildResults) {
		copyLibsToPath(results, Path.join([runningDirectory.toString(), '${config.deployInfo.dest}']));
	}

	static function copyLibsToPath(results:BuildResults, deployPath) {
		for (lib in results.libs) {
			if (config.verbose)
				trace('\t${lib.file.withExtension(lib.ext)}\t\t->\t\t$deployPath');
			copyFile(new Path(FileSystem.fullPath(Path.join([lib.toString()]))),
				new Path(FileSystem.fullPath(Path.join([deployPath, lib.file.withExtension(lib.ext)]))));
		}
	}
}
