var page = require('webpage').create(),
    system = require('system'),
    address, output, size;

if (system.args.length < 3 || system.args.length > 5) {
    console.log('Usage: rasterize.js URL filename [paperwidth*paperheight|paperformat] [zoom]');
    console.log('  paper (pdf output) examples: "5in*7.5in", "10cm*20cm", "A4", "Letter"');
    phantom.exit(1);
} else {
    address = system.args[1];
    output = system.args[2];
    size = system.args[3]
    zoom = system.args[4]
    page.zoomFactor = zoom;
    page.viewportSize = { width: parseInt(size), height: 20 };
    page.open(address, function (status) {
        if (status !== 'success') {
            console.log('Unable to load the address! ' + address);
            phantom.exit();
        } else {
            window.setTimeout(function () {
                page.render(output);
                phantom.exit();
            }, 200);
        }
    });
}
