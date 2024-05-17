const env = {
	memory: new WebAssembly.Memory({initial: 1}),
	__stack_pointer: 0,
};

const zjb = new Zjb();

(function() {
	WebAssembly.instantiateStreaming(fetch("example.wasm"), {env: env, zjb: zjb.imports}).then(function (results) {
		zjb.instance = results.instance;
		results.instance.exports.main();
		console.log("increment by 1", zjb.exports.incrementAndGet(1));
		console.log("increment by 2", zjb.exports.incrementAndGet(2));
	});
})();
