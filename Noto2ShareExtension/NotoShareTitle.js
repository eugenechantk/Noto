// Safari runs this in the page before handing the share to the extension, so
// the capture can carry the page title without a second network fetch.
var NotoShareTitle = function () {};

NotoShareTitle.prototype = {
    run: function (arguments) {
        arguments.completionFunction({
            "title": document.title || "",
            "url": document.URL || ""
        });
    }
};

var ExtensionPreprocessingJS = new NotoShareTitle();
