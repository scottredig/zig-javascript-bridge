const env = {
	memory: new WebAssembly.Memory({initial: 1}),
	__stack_pointer: 0,
};

var zjb = new Zjb();

(function() {
	WebAssembly.instantiateStreaming(fetch("example.wasm"), {env: env, zjb: zjb.imports}).then(function (results) {
		zjb.instance = results.instance;
		results.instance.exports.main();
		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
		console.log("calling zjb exports from javascript", zjb.exports.incrementAndGet(1));
	});
})();
