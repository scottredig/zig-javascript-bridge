const env = {
	memory: new WebAssembly.Memory({initial: 1}),
	__stack_pointer: 0,
};

var zjb = new Zjb();

(function() {
	WebAssembly.instantiateStreaming(fetch("example.wasm"), {env: env, zjb: zjb.imports}).then(function (results) {
		zjb.instance = results.instance;
		results.instance.exports.main();

		console.log("reading zjb global from zig", zjb.exports.checkTestVar());
		console.log("reading zjb global from javascript", zjb.exports.test_var);

		console.log("writing zjb global from zig", zjb.exports.setTestVar());
		console.log("reading zjb global from zig", zjb.exports.checkTestVar());
		console.log("reading zjb global from javascript", zjb.exports.test_var);

		console.log("writing zjb global from javascript", zjb.exports.test_var = 80.80);
		console.log("reading zjb global from zig", zjb.exports.checkTestVar());
		console.log("reading zjb global from javascript", zjb.exports.test_var);

		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
	});
})();
