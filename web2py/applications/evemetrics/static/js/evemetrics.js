function updateQueryStringParameter(uri, key, value) {
  var re = new RegExp("([?&])" + key + "=.*?(&|$)", "i");
  var separator = uri.indexOf('?') !== -1 ? "&" : "?";
  if (uri.match(re)) {
    return uri.replace(re, '$1' + key + "=" + value + '$2');
  }
  else {
    return uri + separator + key + "=" + value;
  }
}

function LoadAddToContainer(which, page, extra, all)
{
  var v = $("#addtoparentcontainer");
  v.html('<img src="static/images/loader2.gif" style="padding-top:5px">');
  v.fadeIn(500);
  url = "LoadAddToContainer?which=" + which + "&page=" + page + "&" + extra;
  if (all)
    url += "&all=1"
  v.load(url);
}

function ToggleExpand(a) {
  $("#" + a).toggle()
}

function strip(html)
{
   var tmp = document.createElement("DIV");
   tmp.innerHTML = html;
   return tmp.textContent||tmp.innerText;
}

var tableSorterSortMethod = function(node)  
{  
    // extract data from markup and return it  
    var v = $(node);
    var h = strip(v.html());
    ret = v.html();
    if (h != undefined) {
      ret = h.replace(/,/gi, "");
      ret = ret.replace(/-/gi, ".");
    }
    return ret;
} 

function Goto(url)
{
  window.parent.location.href = url;
	window.location.href = url;
}


$(document).ready(function() { 
    $(".zebra tr:odd").addClass("alt"); 
    $(".tt").easyTooltip();
    sh_highlightDocument();
} 
); 

function stripTag(bTag, eTag, html) {
    while (true) {
        var beg_idx = html.indexOf(bTag);
        var end_idx = html.indexOf(eTag, beg_idx);
        if (beg_idx > 1 && beg_idx < end_idx) {
            var sub_str = html.substring(beg_idx, end_idx+eTag.length);
            var sub_rep = $(sub_str).html();
            if (sub_rep == "") sub_rep = $(sub_str).val();
            html = html.replace(sub_str, sub_rep);
        } else {
            break;
        }
    }
    return html;
}

function exportToExcel(elementId) {
    var html = "<table>"+document.getElementById(elementId).innerHTML+"</table>";
    html = stripTag("<a ", "</a>", html);
    html = stripTag("<input ", ">", html);
    html = stripTag("<br", ">", html);
    html = html.replace(/,/gi, "");
    if (window.ActiveXObject) {
        alert('This feature is only supported in a real browser such as Firefox')
    } else {
        window.location = 'data:application/vnd.ms-excel;charset=utf8,' + encodeURIComponent(html);
    }
}

function toggleChecked(status) {
    $(".rowchk").each(function() {
        $(this).attr("checked",status);
})
}


function AddFormattingToolbar(textarea, type) {
  if ((typeof(document["selection"]) == "undefined")
   && (typeof(textarea["setSelectionRange"]) == "undefined")) {
    return;
  }

  w = 140
  var t = document.createElement("table");
  t.width = "100%";
  r = t.insertRow(-1);
  c_tb = r.insertCell(-1);
  c_tb.id = 'tb';
  c_tbr = r.insertCell(-1);
  c_tbr.id = 'tbr';
  c_tbr.width = w;
  textarea.parentNode.insertBefore(t, textarea.nextSibling);

  function addButton(id, title, fn, width) {
    var a = document.createElement("a");
    a.href = "javascript:void(0);";
    a.id = id;
    a.title = title;
    a.onclick = function() { fn() };
    a.tabIndex = 400;
    if (width) {
        a.style.width = width + 'px';
    }
    toolbar.appendChild(a);
  }

function GetCaretPosition(control) 
{
var CaretPos = 0;
// IE Support
if (document.selection) 
{
control.focus();
var Sel = document.selection.createRange ();
var Sel2 = Sel.duplicate();
Sel2.moveToElementText(control);
var CaretPos = -1;
while(Sel2.inRange(Sel))
{
Sel2.moveStart('character');
CaretPos++;
}
}

// Firefox support

else if (control.selectionStart || control.selectionStart == '0')
CaretPos = control.selectionStart;

return (CaretPos);

}




function SetCaretPosition(ctrl, pos){
    if(ctrl.setSelectionRange)
    {
        ctrl.focus();
        ctrl.setSelectionRange(pos,pos);
    }
    else if (ctrl.createTextRange) {
        var range = ctrl.createTextRange();
        range.collapse(true);
        range.moveEnd('character', pos);
        range.moveStart('character', pos);
        range.select();
    }
}

function DoEncloseSelection2(textarea, prefix, suffix) {
    textarea.focus();
    pos = GetCaretPosition(textarea);
    var start, end, sel, scrollPos, subst;
    if (typeof(document["selection"]) != "undefined") {
      sel = document.selection.createRange().text;
    } else if (typeof(textarea["setSelectionRange"]) != "undefined") {
      start = textarea.selectionStart;
      end = textarea.selectionEnd;
      scrollPos = textarea.scrollTop;
      sel = textarea.value.substring(start, end);
    }

    if (sel.match(/ $/)) { // exclude ending space char, if any
      sel = sel.substring(0, sel.length - 1);
      suffix = suffix + " ";
    }

    subst = prefix + sel + suffix;

    if (typeof(document["selection"]) != "undefined") {
      var range = document.selection.createRange().text = subst;
      if (sel.length == 0)
        p = pos + 3;
      else
        p = pos + subst.length;
      SetCaretPosition(textarea, p);
    } else if (typeof(textarea["setSelectionRange"]) != "undefined") {
      textarea.value = textarea.value.substring(0, start) + subst +
                       textarea.value.substring(end);
         
      if (sel) {
        textarea.setSelectionRange(start + subst.length, start + subst.length);
      } else {
        textarea.setSelectionRange(start + prefix.length, start + prefix.length);
      }
      textarea.scrollTop = scrollPos;
    }
  }


function encloseSelection(prefix, suffix) {
    DoEncloseSelection2(textarea, prefix, suffix);
}
  
  function InsertLink()
  {

    var txt = prompt("Insert the address of the site you want to link to", "");
    if (txt == null)
        return;
    prefix = "[url="+txt+"]"
    suffix = "[/url]";
    textarea.focus();
    var start, end, sel, scrollPos, subst;
    if (typeof(document["selection"]) != "undefined") {
      sel = document.selection.createRange().text;
    } else if (typeof(textarea["setSelectionRange"]) != "undefined") {
      start = textarea.selectionStart;
      end = textarea.selectionEnd;
      scrollPos = textarea.scrollTop;
      sel = textarea.value.substring(start, end);
    }

    if (sel.match(/ $/)) { // exclude ending space char, if any
      sel = sel.substring(0, sel.length - 1);
      suffix = suffix + " ";
    }

    subst = prefix + sel + suffix;

    if (typeof(document["selection"]) != "undefined") {
      var range = document.selection.createRange().text = subst;
      textarea.caretPos -= suffix.length;
    } else if (typeof(textarea["setSelectionRange"]) != "undefined") {
      textarea.value = textarea.value.substring(0, start) + subst +
                       textarea.value.substring(end);
      if (sel) {
        textarea.setSelectionRange(start + subst.length, start + subst.length);
      } else {
        textarea.setSelectionRange(start + prefix.length, start + prefix.length);
      }
      textarea.scrollTop = scrollPos;
    }
  }


  var toolbar = document.createElement("span");
  toolbar.className = "toolbar";

  addButton("smile", ":)", function() {
    encloseSelection(":)", "");
  });

  addButton("sad", ":(", function() {
    encloseSelection(":(", "");
  });

  addButton("wide", ":D", function() {
    encloseSelection(":D", "");
  });
  
  addButton("grin", ";)", function() {
    encloseSelection(";)", "");
  });
      addButton("shocked", ":|", function() {
        encloseSelection(":|", "");
      });

      addButton("surprised", ":o", function() {
        encloseSelection(":o", "");
      });

      addButton("cry", ":'(", function() {
        encloseSelection(":'(", "");
      });


      addButton("ashamed", ":$", function() {
        encloseSelection(":$", "");
      });

      addButton("confused", ":S", function() {
        encloseSelection(":S", "");
      });
      addButton("tongue", ":p", function() {
        encloseSelection(":p", "");
      });
      addButton("mad", ":@", function() {
        encloseSelection(":@", "");
      });
      addButton("star", "(*)", function() {
        encloseSelection("(*)", "");
      });
      addButton("shades", "B-)", function() {
        encloseSelection("B-)", "");
      });
      addButton("dizzy", "S-|", function() {
        encloseSelection("S-|", "");
      });
//    addButton("ill", ":-%", function() {
//       encloseSelection(":-%", "");
//    });
      addButton("scrooge", ";-(", function() {
        encloseSelection(";-(", "");
      });
  
  a = c_tb;
  a.appendChild(toolbar);

  var toolbar = document.createElement("span");
  toolbar.className = "toolbar";

  
  addButton("bold", "Bold text: [b]Example[/b] (ctrl-b)", function() {
    encloseSelection("[b]", "[/b]");
  });

  addButton("italics", "Italics text: [i]Example[/i] (ctrl-i)", function() {
    encloseSelection("[i]", "[/i]");
  });
  addButton("underline", "Underlined text: [u]Example[/u] (ctrl-u)", function() {
    encloseSelection("[u]", "[/u]");
  });
  
  addButton("center", "Centered text: [c]Example[/c]", function() {
    encloseSelection("[c]", "[/c]");
  });

      addButton("link", "Insert a Link: [url=http://evemetrics]Example[/url]", function() {
        InsertLink();
      });
  
  addButton("red", "Coloured text: [colR]Example[/col]", function() {
     encloseSelection("[colR]", "[/col]");
  }, 8);
  addButton("green", "Coloured text: [colG]Example[/col]", function() {
     encloseSelection("[colG]", "[/col]");
  }, 8);
  addButton("blue", "Coloured text: [colB]Example[/col]", function() {
     encloseSelection("[colB]", "[/col]");
  }, 8);
      addButton("grey", "Coloured text: [colGr]Example[/col]", function() {
         encloseSelection("[colGr]", "[/col]");
      }, 8);
       addButton("yellow", "Coloured text: [colY]Example[/col]", function() {
          encloseSelection("[colY]", "[/col]");
      }, 8);
  a = c_tbr
  a.appendChild(toolbar);

}

function GetPrettyValueForGoal(goal, goalDirection, goalType)
{
    var goalSelector = goalDirection + goalType;
    var v = "";
    if (goalSelector == "UV")
      v = "Value should be increasing"
    else if (goalSelector == "DV")
      v = "Value should be decreasing"
    else if (goalSelector == "SP")
      v = "Value should be stable within " + goal + " %"
    else if (goalSelector == "AV")
      v = "Value should be be above " + goal
    else if (goalSelector == "BV")
      v = "Value should be be below " + goal
    else if (goalSelector == "AP")
      v = "Value should increase weekly by " + goal + " %"
    else if (goalSelector == "BP")
      v = "Value should decrease weekly by " + goal + " %"
    else if (goalSelector == "NA")
      v = "Do not show goal arrow"
    else if (goalSelector == "NN")
      v = "No goal"
    return v;
}

// parseUri 1.2.2
// (c) Steven Levithan <stevenlevithan.com>
// MIT License

function parseUri (str) {
  var o   = parseUri.options,
    m   = o.parser[o.strictMode ? "strict" : "loose"].exec(str),
    uri = {},
    i   = 14;

  while (i--) uri[o.key[i]] = m[i] || "";

  uri[o.q.name] = {};
  uri[o.key[12]].replace(o.q.parser, function ($0, $1, $2) {
    if ($1) uri[o.q.name][$1] = $2;
  });

  return uri;
};

parseUri.options = {
  strictMode: false,
  key: ["source","protocol","authority","userInfo","user","password","host","port","relative","path","directory","file","query","anchor"],
  q:   {
    name:   "queryKey",
    parser: /(?:^|&)([^&=]*)=?([^&]*)/g
  },
  parser: {
    strict: /^(?:([^:\/?#]+):)?(?:\/\/((?:(([^:@]*)(?::([^:@]*))?)?@)?([^:\/?#]*)(?::(\d*))?))?((((?:[^?#\/]*\/)*)([^?#]*))(?:\?([^#]*))?(?:#(.*))?)/,
    loose:  /^(?:(?![^:@]+:[^:@\/]*@)([^:\/?#.]+):)?(?:\/\/)?((?:(([^:@]*)(?::([^:@]*))?)?@)?([^:\/?#]*)(?::(\d*))?)(((\/(?:[^?#](?![^?#\/]*\.[^?#\/.]+(?:[?#]|$)))*\/?)?([^?#\/]*))(?:\?([^#]*))?(?:#(.*))?)/
  }
};

function ToggleSettings() {
    var s = $.cookie("showFilters");
    if (s == 1) {
        s = 0;
        $("#counterform").hide();
        $("#togglesettings").html("Show Settings")
    } else {
        s = 1;
        $("#counterform").show();
        $("#togglesettings").html("Hide Settings")
    }
    $.cookie("showFilters", s, {expires: 365});
}