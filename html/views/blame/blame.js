var blame;

// Create a new Blame object
// obj: PBGitTree object

var Blame = function(obj) {
    this.object = obj;

    this.notificationID = null;
};

var selectBlame = function(a) {
    Controller.selectBlame_(a);
}

var loadBlame = function(blameObject, currentRef) {
    // These are only the things we can do instantly.
    // Other information will be loaded later by loadBlameDetails,
    // Which will be called from the controller once
    // the blame details are in.

    if (blame && blame.notificationID)
        clearTimeout(blame.notificationID);

    blame = new Blame(blameObject);
    blame.currentRef = currentRef;

    scroll(0, 0);

    blame.notificationID = setTimeout(function() {
        if (!blame.fullyLoaded)
            notify("Loading blame…", 0);
        blame.notificationID = null;
    }, 500);

}

var loadBlameDetails = function(data)
{
    if (blame.notificationID)
        clearTimeout(blame.notificationID)
    else
        $("notification").style.display = "none";

    highlightBlame(data, $("blame"));

    hideNotification();
}
