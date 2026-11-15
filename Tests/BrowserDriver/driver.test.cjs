const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
let mutation;
class Element {
  constructor(tag, label, type = '') { this.tagName = tag; this.label = label; this.type = type; this.isConnected = true; this.events = []; this.disabled = false; this.options = []; }
  getAttribute(name) { return name === 'aria-label' ? this.label : null; }
  closest(selector) { return (this.hidden && selector.includes('[hidden]')) || (this.tagName === 'INPUT' && selector.includes('script,style')) ? this : null; }
  getBoundingClientRect() { return {width:100,height:20}; }
  matches(selector) {
    if (selector.startsWith('input[type=')) return this.tagName === 'INPUT' && selector.includes('type=\"' + this.type + '\"');
    return this.tagName === 'TEXTAREA' || (this.tagName === 'INPUT' && !['file','checkbox','radio','submit','button'].includes(this.type));
  }
  click() { this.clicked = (this.clicked || 0) + 1; }
  scrollIntoView() {}
  focus() {}
  dispatchEvent(event) { this.events.push(event.type); }
}
class Input extends Element {
  get value() { return this._value || ''; }
  set value(value) { this._value = value; }
}
const button = new Element('BUTTON','Save');
const input = new Input('INPUT','Name','text'); input.value = 'DO NOT CAPTURE FIELD VALUE';
const password = new Input('INPUT','Password','password'); password.value = 'DO NOT CAPTURE PASSWORD';
const file = new Input('INPUT','Upload','file');
const otp = new Input('INPUT','Code','text'); otp.autocomplete = 'one-time-code';
const select = new Element('SELECT','Color'); select.options = [{text:'Red',value:'r'},{text:'Blue',value:'b'}];
const hidden = new Element('BUTTON','Invisible'); hidden.hidden = true;
const parent = new Element('P','');
const textNodes = [{parentElement:parent,textContent:'Welcome to the fixture'}, {parentElement:input,textContent:'PRIVATE EDITABLE TEXT'}];
const document = {body:{}, documentElement:{}, title:'Fixture',
  querySelectorAll:() => [button,input,password,otp,select,hidden,file], getElementById:() => null,
  createTreeWalker:() => { let i = 0; return {nextNode:() => textNodes[i++] || null}; }};
const sandbox = {document, location:{href:'https://example.test/path?token=SECRET#private'},
  MutationObserver:class {constructor(callback) {mutation = callback;} observe() {}},
  addEventListener:() => {}, getComputedStyle:() => ({visibility:'visible',display:'block'}),
  NodeFilter:{SHOW_TEXT:4}, crypto:{randomUUID}, URL, Date, TextEncoder, atob,
  File: class {constructor(chunks,name) {this.name=name;this.size=chunks.reduce((s,c)=>s+c.byteLength,0);}},
  DataTransfer: class {constructor() {this.files=[];this.items={add:f=>this.files.push(f)};}},
  Event:class {constructor(type) {this.type = type;}}, HTMLInputElement:Input, HTMLTextAreaElement:Input,
  innerHeight:1000, window:{scrollBy: value => {sandbox.scroll = value;}}, history:{back:() => {sandbox.back = true;}}};
vm.createContext(sandbox);
vm.runInContext(readFileSync('browser-extension/driver.js','utf8'),sandbox);
const driver = sandbox.__newtDriver, session = randomUUID();
function command(snapshot, action) { return {id:randomUUID(),session,document:snapshot.document,revision:snapshot.revision,expiresAt:new Date(Date.now()+20000).toISOString(),action:{target:0,value:'',...action}}; }
let page = driver.snapshot(session);
assert.deepEqual(Array.from(page.controls, c => c.label), ['Save','Name','Color','Upload']);
assert.equal(page.page.url,'https://example.test/path');
assert(!JSON.stringify(page).includes('SECRET'));
assert(!JSON.stringify(page).includes('PRIVATE EDITABLE'));
assert(!JSON.stringify(page).includes('DO NOT CAPTURE'));
assert.equal(page.controls[1].editable,true);
assert.deepEqual(Array.from(page.controls[2].options),['Red','Blue']);
assert.throws(() => driver.act(command(page,{kind:'click',target:99})), /no longer available/);
driver.act(command(page,{kind:'type',target:2,value:'नमस्ते 🌍'}));
assert.equal(input.value,'नमस्ते 🌍');
assert.deepEqual(input.events,['input','change']);
assert.throws(() => driver.act(command(page,{kind:'click',target:1})),/page changed/);
page = driver.snapshot(session);
mutation();
assert.throws(() => driver.act(command(page,{kind:'click',target:1})),/page changed/);
page = driver.snapshot(session);
const expired = command(page,{kind:'click',target:1}); expired.expiresAt = new Date(0).toISOString();
assert.throws(() => driver.act(expired), /page changed/);
const wrongDocument = command(page,{kind:'click',target:1}); wrongDocument.document = randomUUID();
assert.throws(() => driver.act(wrongDocument), /page changed/);
driver.act(command(page,{kind:'click',target:1})); assert.equal(button.clicked,1);
page = driver.snapshot(session); button.label = 'Different action';
assert.throws(() => driver.act(command(page,{kind:'click',target:1})), /no longer available/);
mutation(); page = driver.snapshot(session);
driver.act(command(page,{kind:'select',target:3,value:'Blue'})); assert.equal(select.value,'b');
page = driver.snapshot(session);
assert.throws(() => driver.act(command(page,{kind:'select',target:3,value:'Green'})), /unique option/);
assert.throws(() => driver.act(command(page,{kind:'type',target:1,value:'bad'})), /not editable/);
driver.act(command(page,{kind:'scroll',value:'down'})); assert.equal(sandbox.scroll.top,800);
page = driver.snapshot(session);
assert.equal(page.controls[3].role,'file'); assert.equal(page.controls[3].editable,false);
assert.throws(() => driver.act(command(page,{kind:'click',target:4})), /approved upload/);
assert.throws(() => driver.act(command(page,{kind:'upload',target:4})), /Invalid upload/);
assert.throws(() => driver.act(command(page,{kind:'upload',target:4}),{fileName:'test.txt',size:4,chunks:['YQ==']}), /Incomplete upload/);
driver.act(command(page,{kind:'upload',target:4}),{fileName:'test.txt',size:3,chunks:['YWJj']});
assert.equal(file.files[0].size,3); assert.equal(file.files[0].name,'test.txt');
assert.deepEqual(file.events,['input','change']);
page = driver.snapshot(session); sandbox.location.href = 'https://example.test/another';
assert.throws(() => driver.act(command(page,{kind:'click',target:1})),/page changed/);
console.log('PASS browser DOM contracts: privacy, exact controls, Unicode input, select, stale document/revision, expiry, and no mutation replay');
