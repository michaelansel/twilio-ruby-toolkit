var var_call_complete = true;
function call_complete() {
  if( var_call_complete ){ reset(true); return; }

  console.log( "Marking call as completed" );

  var_call_complete = true;

  var kids = $('#call_flow').children();
  if( ! kids.eq(kids.length-1).hasClass('.call-divider') ) {
    notify('Call Complete');
    add_to_call_flow( $("<div class='call-divider'/>") );
  }
}
function reset(silent){
  if( !silent ){
    add_to_call_flow( $("<div class='call-divider'/>") );
  }
  if(gathering) { gathering = false; gather_complete(); };
  if(recording) { recording = false; record_complete(); };
  if(pausing)   { pausing = false;   cancel_pause();    };


  /* Disable Hangup button and CallFlow updates */
  $('#hangup')[0].disabled=var_call_complete;

  update_call_flow_interval(3000);
  if( update_ptr ) {
    toggle_auto_update_call_flow();
  }
}
function call_active() {
  if( !var_call_complete ){ return; }

  console.log( "Marking call as active" );

  var_call_complete = false;

  notify('Call Active');

  /* Enable Hangup button and CallFlow updates */
  $('#hangup')[0].disabled=var_call_complete;

  update_call_flow();
  if( !update_ptr ) {
    toggle_auto_update_call_flow();
  }
}
$(function(){reset()}); /* Reset everything on page load */



/******* Call Flow Queue Monitor *******/

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


/****** Auto-Update Call Flow ******/
var update_ptr = false;
var update_interval = 1500;
function toggle_auto_update_call_flow() {
  if( update_ptr ) {
    window.clearInterval(update_ptr);
    update_ptr = false;
    $('#auto_refresh_button')[0].textContent = "Enable Auto-Refresh"
  } else {
    update_ptr = window.setInterval(function() {
      if( !pausing && (!gathering /*|| digits_pressed*/) && !recording ) { update_call_flow(); }
    }, update_interval);
    $('#auto_refresh_button')[0].textContent = "Disable Auto-Refresh"
    update_call_flow();
  }
}
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

/***** AJAX Callback Handler *****/
function add_json_to_call_flow_queue(data, status){
  console.log(data);
  $.each(data, function(){

    var method = this.method;
    var params = this.params;
    if( eval("typeof " + method + " == 'function'") ){
      var func = eval(method);

      console.log('Queueing: '+method+'('+params+')');
      call_flow_queue.push(function(){
        if( method != "call_complete" ) { call_active(); }
        console.log('Evaluating: '+method+'('+params+')');
        func(params);
      });

      if( call_flow_queue_monitor_ptr == 0 ) {
        call_flow_queue_monitor_ptr = 
              setTimeout(call_flow_queue_monitor, 500);
      }

    /*} else if(typeof this.call_complete == "boolean") {
      if( this.call_complete ) {
        call_complete();
      }*/

    } else {
      call_active();
      console.warn('Not a function: '+method+' => '+params);
    }

    return true;
  });
}

function rand_int(){ return Math.floor(Math.random()*10000); };
function update_call_flow(){
    $.ajax({
			type: "GET",
			url: '/call-sim/ajax',
			data: {action:'next', rand:rand_int()},
			success: add_json_to_call_flow_queue,
      error: function() { /* ignore errors */ },
			dataType: 'json',
      timeout: 3*update_interval
		});
}


/****** Outgoint AJAX Calls ******/
$.ajaxSetup({
  error: function(xhr,status,error) {
    console.error("AJAX Request Failed!",xhr,status,error);
  }
})

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
  /*update_call_flow();
  if( !update_ptr ) {
    toggle_auto_update_call_flow();
  }*/
}



/***** Control Panel "Controllers" *****/

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



/****** Call Action Handlers *******/

function add_to_call_flow( elem ) {
  elem.appendTo('#call_flow');
  $('html,body').animate({scrollTop: $('body').height()},500);
  return elem;
}

function say(opts) {
  var e = add_to_call_flow( $('<div class="say"><span></span></div>') );
  $('span',e).text(opts.body);
}

function play(str) {
  var e = add_to_call_flow( $('<div class="play"><span>Playing file at <a target="_new"></a></span></div>') );
  $('a',e).text(str).href=str;
  $('<embed src="'+str+'" autostart=true loop=false>').appendTo($('div.play', e));
}

var gathering = false;
var digits_pressed = false;
function gather(opts) {
  gathering = true;
  digits_pressed = false;
  add_to_call_flow( $('<div class="gather"><span>Gathering...</span></div>') );
  $('#gather_box').show()

  countdown(opts.timeout,function(){
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
function record(opts) {
  recording = true;
  add_to_call_flow( $('<div class="gather"><span>Recording...</span></div>') );
  $('#record_box').show()

  countdown(opts.timeout,function(){
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

  countdown(t,function(){
    pausing = false;
  });

  add_to_call_flow( $('<div class="pause">Pausing for '+parseInt(t)+' second(s)</div>') );
}
function cancel_pause() {
  cancel_countdown();
  pausing = false;
}

function parse(body) {
  var e = add_to_call_flow( $('<div class="notify">Parsing TwiML Response:<div class="twiml"></div></div>') );
  $('.twiml', e).text(body);
}
function calling(url) {
  var e = add_to_call_flow( $('<div class="call notify">Simulating phone call to URL: <a></a></div>') );
  $('a', e).text(url);
  $('a', e).href = url;
}
function redirect(url) {
  var e = add_to_call_flow( $('<div class="redirect notify">Redirecting to URL: <a></a></div>') );
  $('a', e).text(url);
  $('a', e).href = url;
}
function skip(twiml) {
  var e = add_to_call_flow( $('<div class="notify">NOT Parsing:<div class="twiml"></div></div>') );
  $('.twiml', e).text(twiml);
}
function hangup(msg) {
  var e = add_to_call_flow( $('<div class="hangup notify">Hanging up:<span class="msg"></span></div>') );
  $('.msg',e).text(msg);
  call_complete();
}










function notify(body) {
  console.warn('Notify: '+body);
  add_to_call_flow( $('<div class="notify"/>') ).html(body);
}
function twiml(body) {
  console.warn('TwiML: '+body);
  add_to_call_flow( $('<div class="twiml"/>').text(body) );
}
function noop() {
  console.warn('NOOP');
  return;
}
