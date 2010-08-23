// If we run from a Safari instance, we don't
// have a Controller object. Instead, we fake it by
// using the console
if (typeof Controller == 'undefined') {
    Controller = console;
    Controller.log_ = console.log;
}

var highlightBlame = function(blame, element) {
    if (!blame || blame == "")
        return;

    var start = new Date().getTime();
    element.className = "blame"
    var content = blame.escapeHTML().replace(/\t/g, "    ");;

    var startname = "";
    var endname = "";
    var blameContent = "";
    var finalContent = "";
    var lines = content.split('\n');
    var binary = false;
    var mode_change = false;
    var old_mode = "";
    var new_mode = "";

    var hunk_start_line_1 = -1;
    var hunk_start_line_2 = -1;

    var header = false;
	var inTable = false;

    var finishContent = function()
    {
        var title = startname;
        var binaryname = endname;
        if (endname == "/dev/null") {
            binaryname = startname;
            title = startname;
        }
        else if (startname == "/dev/null")
            title = endname;
        else if (startname != endname)
            title = startname + " renamed to " + endname;

        if (binary && endname == "/dev/null") { // in cases of a deleted binary file, there is no blame/file to display
            blameContent = "";
            file_index++;
            startname = "";
            endname = "";
            return;             // so printing the filename in the file-list is enough
        }

        if (!binary && (blameContent != ""))  {
            finalContent +=     '<div class="blameContent">' +
                                '<div class="lines">' + blameContent + "</div>" +
                            '</div>';
        }
        else {
            if (binary) {
				finalContent += "<div>Binary file blamers</div>";
            }
        }

        blameContent = "";
        startname = "";
        endname = "";
    }
	
	blameContent += '<table>';
	blameContent += '<col><col><col><col width="100%">';

    for (var lineno = 0, lindex = 0; lineno < lines.length; lineno++) {
        var l = lines[lineno];

		blameContent += '<tr>';
		blameContent += '<td class="lineno">' + l + "</td>";
		blameContent += '</tr>';
    }
	
	blameContent += '</table>';

    finishContent();

    element.innerHTML = finalContent;

    // TODO: Replace this with a performance pref call
    if (false)
        Controller.log_("Total time:" + (new Date().getTime() - start));
}
