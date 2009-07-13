function rand_int(){ return Math.floor(Math.random()*10000); };
var call_complete = true;
function update_call_flow(){
    $.ajax({
			type: "GET",
			url: '/call-sim/ajax',
			data: {action:'next', rand:rand_int()},
			success: add_json_to_call_flow_queue,
			dataType: 'json',
      timeout: 3*update_interval
		});
}

var call_flow_queue = new Array();
var call_flow_queue_monitor_ptr = 0;
function call_flow_queue_monitor() {
  clearTimeout(call_flow_queue_monitor_ptr);
  if( !pausing &&  call_flow_queue.length > 0 ) {
    call_flow_queue.shift()();
  }
  if( call_flow_queue.length > 0 ) {
    call_flow_queue_monitor_ptr = 
          setTimeout(call_flow_queue_monitor, 500);
  } else {
    call_flow_queue_monitor_ptr = 0;
  }
}

function add_json_to_call_flow_queue(data, status){
  console.log(data);
  $.each(data, function(){

    var method = this.method;
    var params = this.params;
    var func = eval(method);

    if( $.isFunction(func) ) {

      call_flow_queue.push(function(){
        console.log('Evaluating: '+method+'('+params+')');
        func(params);
      });

      if( call_flow_queue_monitor_ptr == 0 ) {
        call_flow_queue_monitor_ptr = 
              setTimeout(call_flow_queue_monitor, 500);
      }

    } else {
      console.log('Unable to process: '+this.method+' => '+this.params);
    }

    return true;
  });
}


var update_ptr = false;
var update_interval = 1500;
function update_call_flow_interval(interval) {
  if( pausing ) { return false; };
  if( interval != null ) { update_interval = interval; };

  if( update_ptr ) { /* If auto updates are enabled right now */
    window.clearInterval(update_ptr);
    update_ptr = window.setInterval(function() {
      if( !pausing && !gathering && !recording ) { update_call_flow(); }
    }, update_interval);
  }
}

function toggle_auto_update_call_flow() {
  if( update_ptr ) {
    window.clearInterval(update_ptr);
    update_ptr = false;
    $('#auto_refresh_button')[0].textContent = "Enable Auto-Refresh"
  } else {
    update_ptr = window.setInterval(function() {
      if( !pausing && (!gathering || digits_pressed) && !recording ) { update_call_flow(); }
    }, update_interval);
    $('#auto_refresh_button')[0].textContent = "Disable Auto-Refresh"
    update_call_flow();
  }
}

$(toggle_auto_update_call_flow);

function ajax_call(action, options) {
  if(options == null) { options = {} }
  var params = {};
  params["action"] = action;
  params["rand"] = rand_int();

  switch(action) {
    case 'call_url':
      if(options["url"]) {
        params["url"] = options["url"];
      } else {
        params["url"] = $('form#call_url')[0].url.value;
      }
      notify('Requesting a call to '+params["url"]);
      break;
    case 'press_digit':
      params["digit"] = options["digit"];
      notify('Sending key press ('+params['digit']+') to handler');
      digits_pressed = true;
      break;
    case 'gather_timeout':
      /* No extra params */
      break;
    case 'record_timeout':
      /* No extra params */
      break;
    case 'hangup':
      /* No extra params */
      notify('Attempting to hangup');
      if(gathering) { gather_complete(); };
      if(recording) { record_complete(); };
      if(pausing)   { cancel_pause();    };
      break;
    case 'next':
      /* No extra params */
      break;
  }
  $.get('/call-sim/ajax', params, add_json_to_call_flow_queue, 'json');
  update_call_flow();
  if( !update_ptr ) {
    toggle_auto_update_call_flow();
  }
}

var countdown_remaining = 0;
var countdown_ptr = 0;
function countdown(time_in_seconds, callback_on_timeout) {
  $('#countdown').show();
  countdown_remaining = time_in_seconds;

  if( countdown_ptr != 0 ) {
    console.log("Trying to double up; Canceling previous countdown ("+countdown_ptr+")");
    cancel_countdown();
  }

  countdown_ptr = setInterval(function(){
    countdown_remaining = countdown_remaining - 1;

    if( countdown_remaining > 0 ) {
      /* Keep counting */
      $('#countdown').text(""+countdown_remaining);

    } else {
      /* Timeout */
      cancel_countdown();
      if($.isFunction(callback_on_timeout)) { callback_on_timeout(); };
    }

  }, 1000);
}
function cancel_countdown() {
  clearInterval(countdown_ptr);
  $('#countdown').hide();
  $('#countdown').text("");
  countdown_remaining = 0;
  countdown_ptr = 0;
}

function add_to_call_flow( elem ) {
  elem.appendTo('#call_flow')[0].scrollIntoView(true);
  return elem;
}

function add_call_divider() {
  add_to_call_flow( $("<div class='call-divider'/>") );
}

function say(str) {
  add_to_call_flow( $('<div class="say"><span>'+str+'</span></div>') );
}
function play(str) {
  var e = add_to_call_flow( $('<div class="play"><span>Playing file at <a target="_new" href="'+str+'">'+$('<div/>').text(str).html()+'</a></span></div>') );
  $('<embed src="'+str+'" autostart=true loop=false>').appendTo($('div.play', e));
}

var gathering = false;
var digits_pressed = false;
function gather(t) {
  gathering = true;
  digits_pressed = false;
  add_to_call_flow( $('<div class="gather"><span>Gathering...</span></div>') );
  $('#gather_box').show()

  countdown(t,function(){
    $('#gather_box').hide()
    add_to_call_flow( $('<div class="gather timeout"><span>Gather timed out</span></div>') );
    ajax_call('gather_timeout');
    gathering = false;
  });
}
function gather_complete() {
  cancel_countdown();
  $('#gather_box').hide();

  if( gathering ) { /* don't spam the user if this gets called multiple times */
    add_to_call_flow( $('<div class="gather complete"><span>Done gathering</span></div>') );
  }
  gathering = false;
  digits_pressed = false;
}

var recording = false;
function record(t) {
  recording = true;
  add_to_call_flow( $('<div class="gather"><span>Recording...</span></div>') );
  $('#record_box').show()

  countdown(t,function(){
    $('#record_box').hide()
    add_to_call_flow( $('<div class="record timeout"><span>Record timed out</span></div>') );
    ajax_call('record_timeout');
    recording = false;
  });
}
function record_complete() {
  cancel_countdown();
  $('#record_box').hide();
  if( recording ) { /* don't spam the user if this gets called multiple times */
    add_to_call_flow( $('<div class="record complete"><span>Done recording</span></div>') );
  }
  recording = false;
}

var pausing = false;
function pause(t) {
  pausing = true;
  //$('#auto_refresh_button').disabled = true;
  //toggle_auto_update_call_flow();

  countdown(t,function(){
    //toggle_auto_update_call_flow();
    //$('#auto_refresh_button').disabled = false;
    pausing = false;
  });

  add_to_call_flow( $('<div class="pause">Pausing for '+t+' second(s)</div>') );
}
function cancel_pause() {
  cancel_countdown();
  toggle_auto_update_call_flow();
  pausing = false;
}

function call_completed() {
  var kids = $('#call_flow').children();
  if( ! kids.eq(kids.length-1).hasClass('.call-divider') ) {
    notify('Call Complete');
    add_call_divider();
  }

  if(gathering) { gather_complete(); };
  if(recording) { record_complete(); };
  if(pausing)   { cancel_pause();    };

  update_call_flow_interval(3000);
  toggle_auto_update_call_flow();
}

function reload_page() {
  console.log('Reloading page');
  window.location.reload();
}
function notify(body) {
  console.log('Notify: '+body);
  add_to_call_flow( $('<div class="notify"/>') ).html(body);
}
function twiml(body) {
  add_to_call_flow( $('<div class="twiml"/>').text(body) );
}
function noop() {
  return;
}
