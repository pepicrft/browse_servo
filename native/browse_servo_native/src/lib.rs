#![allow(non_local_definitions)]

use dpi::PhysicalSize;
use image::codecs::jpeg::JpegEncoder;
use image::codecs::png::PngEncoder;
use image::{ColorType, ImageEncoder};
use rustler::{Atom, Encoder, Env, Error, NifMap, NifResult, OwnedBinary, ResourceArc, Term};
use servo::resources::{self, Resource, ResourceReaderMethods};
use servo::{
    DevicePoint, EventLoopWaker, InputEvent, JSValue, LoadStatus, MouseButton,
    MouseButtonAction, MouseButtonEvent, MouseMoveEvent, Preferences, RenderingContext,
    RgbaImage, Servo, ServoBuilder, SoftwareRenderingContext, WebView, WebViewBuilder,
    WebViewDelegate,
};
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Arc, OnceLock};
use std::thread;
use std::time::{Duration, Instant};
use url::Url;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        browse_servo,
        rustler,
        supported,
        direct,
        not_found,
        timeout,
        undefined
    }
}

const DEFAULT_WIDTH: u32 = 1280;
const DEFAULT_HEIGHT: u32 = 720;
const DEFAULT_TIMEOUT_MS: u64 = 30_000;

struct RuntimeResource {
    sender: Sender<Command>,
}

static RUNTIME_SENDER: OnceLock<Sender<Command>> = OnceLock::new();

#[derive(Clone)]
struct PageState {
    id: u64,
    title: String,
    url: String,
}

#[derive(Clone, Debug)]
enum NativeValue {
    Undefined,
    Null,
    Boolean(bool),
    Number(f64),
    String(String),
    Array(Vec<NativeValue>),
    Object(BTreeMap<String, NativeValue>),
}

#[derive(NifMap)]
struct Capabilities {
    engine: Atom,
    embedding: Atom,
    javascript: Atom,
    navigation: Atom,
}

#[derive(NifMap)]
struct PageAttrs {
    id: u64,
    title: String,
    url: String,
}

struct CapabilitiesData;

enum Command {
    Capabilities(Sender<Result<CapabilitiesData, String>>),
    OpenPage(String, Sender<Result<PageState, String>>),
    Navigate(u64, String, Sender<Result<PageState, String>>),
    Content(u64, Sender<Result<String, String>>),
    Title(u64, Sender<Result<String, String>>),
    Evaluate(u64, String, Sender<Result<NativeValue, String>>),
    CaptureScreenshot(u64, String, u8, Sender<Result<Vec<u8>, String>>),
    PrintToPdf(u64, Sender<Result<Vec<u8>, String>>),
    Click(u64, String, Sender<Result<(), String>>),
    Fill(u64, String, String, Sender<Result<(), String>>),
    WaitFor(u64, String, u64, Sender<Result<(), String>>),
    Hover(u64, String, Sender<Result<(), String>>),
    SelectOption(u64, String, String, Sender<Result<(), String>>),
    GetText(u64, String, Sender<Result<String, String>>),
    GetAttribute(u64, String, String, Sender<Result<NativeValue, String>>),
    GetCookies(u64, Sender<Result<NativeValue, String>>),
    SetCookie(u64, String, Sender<Result<(), String>>),
    ClearCookies(u64, Sender<Result<(), String>>),
    ClosePage(u64, Sender<Result<(), String>>),
}

#[derive(Default)]
struct Delegate;

impl WebViewDelegate for Delegate {
    fn notify_new_frame_ready(&self, webview: WebView) {
        webview.paint();
    }
}

#[derive(Clone)]
struct WorkerWaker(Arc<AtomicBool>);

impl EventLoopWaker for WorkerWaker {
    fn clone_box(&self) -> Box<dyn EventLoopWaker> {
        Box::new(self.clone())
    }

    fn wake(&self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

struct EmbeddedResourceReader;

impl ResourceReaderMethods for EmbeddedResourceReader {
    fn read(&self, resource: Resource) -> Vec<u8> {
        match resource {
            Resource::BluetoothBlocklist => vec![],
            Resource::DomainList => b"com\norg\nnet\nio\napp\n".to_vec(),
            Resource::HstsPreloadList => vec![],
            Resource::BadCertHTML => BAD_CERT_HTML.as_bytes().to_vec(),
            Resource::NetErrorHTML => NET_ERROR_HTML.as_bytes().to_vec(),
            Resource::BrokenImageIcon => BROKEN_IMAGE_ICON.to_vec(),
            Resource::CrashHTML => CRASH_HTML.as_bytes().to_vec(),
            Resource::DirectoryListingHTML => DIRECTORY_LISTING_HTML.as_bytes().to_vec(),
            Resource::AboutMemoryHTML => ABOUT_MEMORY_HTML.as_bytes().to_vec(),
            Resource::DebuggerJS => DEBUGGER_JS.as_bytes().to_vec(),
        }
    }

    fn sandbox_access_files(&self) -> Vec<PathBuf> {
        vec![]
    }

    fn sandbox_access_files_dirs(&self) -> Vec<PathBuf> {
        vec![]
    }
}

const BAD_CERT_HTML: &str = "<!doctype html><html><body><h1>Bad Certificate</h1><p>${reason}</p></body></html>";
const NET_ERROR_HTML: &str = "<!doctype html><html><body><h1>Network Error</h1><p>${reason}</p></body></html>";
const CRASH_HTML: &str = "<!doctype html><html><body><h1>Crash</h1><pre>${details}</pre></body></html>";
const DIRECTORY_LISTING_HTML: &str = "<!doctype html><html><body><script>function setData(){}</script></body></html>";
const ABOUT_MEMORY_HTML: &str = "<!doctype html><html><body><h1>About Memory</h1></body></html>";
const DEBUGGER_JS: &str = "";
const BROKEN_IMAGE_ICON: &[u8] = &[
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
    6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 255, 255, 63,
    0, 5, 254, 2, 254, 65, 13, 34, 185, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

struct WorkerState {
    servo: Servo,
    rendering_context: Rc<SoftwareRenderingContext>,
    delegate: Rc<Delegate>,
    webviews: HashMap<u64, WebView>,
    next_page_id: u64,
    _waker: Arc<AtomicBool>,
}

#[rustler::nif]
fn new_runtime() -> NifResult<(Atom, ResourceArc<RuntimeResource>)> {
    let sender = RUNTIME_SENDER
        .get_or_init(|| {
            let (sender, receiver) = mpsc::channel();

            thread::Builder::new()
                .name("browse_servo_runtime".into())
                .spawn(move || worker_loop(receiver))
                .expect("failed to spawn browse_servo_runtime");

            sender
        })
        .clone();

    Ok((atoms::ok(), ResourceArc::new(RuntimeResource { sender })))
}

#[rustler::nif]
fn shutdown(_runtime: ResourceArc<RuntimeResource>) -> Atom {
    atoms::ok()
}

#[rustler::nif]
fn capabilities<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
) -> NifResult<(Atom, Term<'a>)> {
    let _ = send_command(&runtime.sender, Command::Capabilities)?;

    let capabilities = Capabilities {
        engine: atoms::browse_servo(),
        embedding: atoms::rustler(),
        javascript: atoms::supported(),
        navigation: atoms::direct(),
    };

    Ok((atoms::ok(), capabilities.encode(env)))
}

#[rustler::nif]
fn open_page<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    url: String,
) -> NifResult<(Atom, Term<'a>)> {
    let page = send_command(&runtime.sender, |reply| Command::OpenPage(url, reply))?;
    Ok((atoms::ok(), page_attrs(page).encode(env)))
}

#[rustler::nif]
fn navigate<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    url: String,
) -> NifResult<(Atom, Term<'a>)> {
    let page = send_command(&runtime.sender, |reply| Command::Navigate(page_id, url, reply))?;
    Ok((atoms::ok(), page_attrs(page).encode(env)))
}

#[rustler::nif]
fn content(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<(Atom, String)> {
    let value = send_command(&runtime.sender, |reply| Command::Content(page_id, reply))?;
    Ok((atoms::ok(), value))
}

#[rustler::nif]
fn title(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<(Atom, String)> {
    let value = send_command(&runtime.sender, |reply| Command::Title(page_id, reply))?;
    Ok((atoms::ok(), value))
}

#[rustler::nif]
fn evaluate<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    expression: String,
) -> NifResult<(Atom, Term<'a>)> {
    let value = send_command(&runtime.sender, |reply| Command::Evaluate(page_id, expression, reply))?;
    Ok((atoms::ok(), encode_native_value(env, &value)))
}

#[rustler::nif]
fn capture_screenshot<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    format: String,
    quality: u8,
) -> NifResult<(Atom, Term<'a>)> {
    let bytes =
        send_command(&runtime.sender, |reply| Command::CaptureScreenshot(page_id, format, quality, reply))?;
    Ok((atoms::ok(), bytes_to_term(env, &bytes)))
}

#[rustler::nif]
fn print_to_pdf<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
) -> NifResult<(Atom, Term<'a>)> {
    let bytes = send_command(&runtime.sender, |reply| Command::PrintToPdf(page_id, reply))?;
    Ok((atoms::ok(), bytes_to_term(env, &bytes)))
}

#[rustler::nif]
fn click(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::Click(page_id, selector, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn fill(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
    value: String,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::Fill(page_id, selector, value, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn wait_for(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
    timeout_ms: u64,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::WaitFor(page_id, selector, timeout_ms, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn hover(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::Hover(page_id, selector, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn select_option(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
    value: String,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::SelectOption(page_id, selector, value, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn get_text(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
) -> NifResult<(Atom, String)> {
    let value = send_command(&runtime.sender, |reply| Command::GetText(page_id, selector, reply))?;
    Ok((atoms::ok(), value))
}

#[rustler::nif]
fn get_attribute<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    selector: String,
    name: String,
) -> NifResult<(Atom, Term<'a>)> {
    let value = send_command(&runtime.sender, |reply| Command::GetAttribute(page_id, selector, name, reply))?;
    Ok((atoms::ok(), encode_native_value(env, &value)))
}

#[rustler::nif]
fn get_cookies<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
) -> NifResult<(Atom, Term<'a>)> {
    let value = send_command(&runtime.sender, |reply| Command::GetCookies(page_id, reply))?;
    Ok((atoms::ok(), encode_native_value(env, &value)))
}

#[rustler::nif]
fn set_cookie(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    cookie_string: String,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::SetCookie(page_id, cookie_string, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn clear_cookies(
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::ClearCookies(page_id, reply))?;
    Ok(atoms::ok())
}

#[rustler::nif]
fn close_page(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<Atom> {
    send_command(&runtime.sender, |reply| Command::ClosePage(page_id, reply))?;
    Ok(atoms::ok())
}

fn worker_loop(receiver: Receiver<Command>) {
    let mut state = match WorkerState::new() {
        Ok(state) => state,
        Err(_) => return,
    };

    while let Ok(command) = receiver.recv() {
        match command {
            Command::Capabilities(reply) => {
                let _ = reply.send(Ok(CapabilitiesData));
            },
            Command::OpenPage(url, reply) => {
                let _ = reply.send(state.open_page(url));
            },
            Command::Navigate(page_id, url, reply) => {
                let _ = reply.send(state.navigate(page_id, url));
            },
            Command::Content(page_id, reply) => {
                let _ = reply.send(state.content(page_id));
            },
            Command::Title(page_id, reply) => {
                let _ = reply.send(state.title(page_id));
            },
            Command::Evaluate(page_id, expression, reply) => {
                let _ = reply.send(state.evaluate(page_id, expression));
            },
            Command::CaptureScreenshot(page_id, format, quality, reply) => {
                let _ = reply.send(state.capture_screenshot(page_id, &format, quality));
            },
            Command::PrintToPdf(page_id, reply) => {
                let _ = reply.send(state.print_to_pdf(page_id));
            },
            Command::Click(page_id, selector, reply) => {
                let _ = reply.send(state.click(page_id, &selector));
            },
            Command::Fill(page_id, selector, value, reply) => {
                let _ = reply.send(state.fill(page_id, &selector, &value));
            },
            Command::WaitFor(page_id, selector, timeout_ms, reply) => {
                let _ = reply.send(state.wait_for(page_id, &selector, timeout_ms));
            },
            Command::Hover(page_id, selector, reply) => {
                let _ = reply.send(state.hover(page_id, &selector));
            },
            Command::SelectOption(page_id, selector, value, reply) => {
                let _ = reply.send(state.select_option(page_id, &selector, &value));
            },
            Command::GetText(page_id, selector, reply) => {
                let _ = reply.send(state.get_text(page_id, &selector));
            },
            Command::GetAttribute(page_id, selector, name, reply) => {
                let _ = reply.send(state.get_attribute(page_id, &selector, &name));
            },
            Command::GetCookies(page_id, reply) => {
                let _ = reply.send(state.get_cookies(page_id));
            },
            Command::SetCookie(page_id, cookie_string, reply) => {
                let _ = reply.send(state.set_cookie(page_id, &cookie_string));
            },
            Command::ClearCookies(page_id, reply) => {
                let _ = reply.send(state.clear_cookies(page_id));
            },
            Command::ClosePage(page_id, reply) => {
                let _ = reply.send(state.close_page(page_id));
            },
        }
    }
}

impl WorkerState {
    fn new() -> Result<Self, String> {
        resources::set(Box::new(EmbeddedResourceReader));

        let rendering_context = Rc::new(
            SoftwareRenderingContext::new(PhysicalSize {
                width: DEFAULT_WIDTH,
                height: DEFAULT_HEIGHT,
            })
            .map_err(|error| format!("{error:?}"))?,
        );

        rendering_context
            .make_current()
            .map_err(|error| format!("{error:?}"))?;

        let waker = Arc::new(AtomicBool::new(false));
        let mut preferences = Preferences::default();
        preferences.network_http_proxy_uri = String::new();
        preferences.network_https_proxy_uri = String::new();

        let servo = ServoBuilder::default()
            .preferences(preferences)
            .event_loop_waker(Box::new(WorkerWaker(waker.clone())))
            .build();

        Ok(Self {
            servo,
            rendering_context,
            delegate: Rc::new(Delegate),
            webviews: HashMap::new(),
            next_page_id: 1,
            _waker: waker,
        })
    }

    fn open_page(&mut self, url: String) -> Result<PageState, String> {
        let url = parse_url(&url)?;
        let webview = self.build_webview(url)?;

        let page_id = self.next_page_id;
        self.next_page_id += 1;
        self.webviews.insert(page_id, webview.clone());

        Ok(self.page_state(page_id, &webview))
    }

    fn navigate(&mut self, page_id: u64, url: String) -> Result<PageState, String> {
        let url = parse_url(&url)?;
        let _ = self.webview(page_id)?;
        let webview = self.build_webview(url)?;
        self.webviews.insert(page_id, webview.clone());
        Ok(self.page_state(page_id, &webview))
    }

    fn content(&mut self, page_id: u64) -> Result<String, String> {
        string_from_value(self.evaluate(page_id, "document.documentElement.outerHTML".into())?)
    }

    fn title(&mut self, page_id: u64) -> Result<String, String> {
        if let Some(title) = self.webview(page_id)?.page_title() {
            return Ok(title);
        }

        string_from_value(self.evaluate(page_id, "document.title".into())?)
    }

    fn evaluate(&mut self, page_id: u64, expression: String) -> Result<NativeValue, String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;

        let stored = Rc::new(RefCell::new(None));
        let callback_stored = stored.clone();

        webview.evaluate_javascript(expression, move |result| {
            *callback_stored.borrow_mut() = Some(result);
        });

        self.spin_until(DEFAULT_TIMEOUT_MS, || stored.borrow().is_none())?;

        let result = match stored.borrow_mut().take() {
            Some(Ok(value)) => Ok(native_value_from_js(value)),
            Some(Err(error)) => Err(format!("{error:?}")),
            None => Err("evaluation_missing_result".into()),
        };

        result
    }

    fn capture_screenshot(
        &mut self,
        page_id: u64,
        format: &str,
        quality: u8,
    ) -> Result<Vec<u8>, String> {
        let image = self.take_screenshot_image(page_id)?;
        encode_image(&image, format, quality)
    }

    fn print_to_pdf(&mut self, page_id: u64) -> Result<Vec<u8>, String> {
        let image = self.take_screenshot_image(page_id)?;
        render_pdf(&image)
    }

    fn click(&mut self, page_id: u64, selector: &str) -> Result<(), String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;
        self.wait_for(page_id, selector, DEFAULT_TIMEOUT_MS)?;
        let point = self.selector_center(page_id, selector)?;

        webview.notify_input_event(InputEvent::MouseMove(MouseMoveEvent::new(point.into())));
        webview.notify_input_event(InputEvent::MouseButton(MouseButtonEvent::new(
            MouseButtonAction::Down,
            MouseButton::Left,
            point.into(),
        )));
        webview.notify_input_event(InputEvent::MouseButton(MouseButtonEvent::new(
            MouseButtonAction::Up,
            MouseButton::Left,
            point.into(),
        )));

        self.spin_for(Duration::from_millis(50));
        Ok(())
    }

    fn fill(&mut self, page_id: u64, selector: &str, value: &str) -> Result<(), String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;
        self.wait_for(page_id, selector, DEFAULT_TIMEOUT_MS)?;

        let script = format!(
            "(() => {{ const el = document.querySelector({selector}); if (!el) return false; if (typeof el.focus === 'function') el.focus(); if ('value' in el) {{ el.value = {value}; }} else {{ el.textContent = {value}; el.setAttribute('value', {value}); }} try {{ el.dispatchEvent(new Event('input', {{ bubbles: true }})); }} catch (_error) {{}} try {{ el.dispatchEvent(new Event('change', {{ bubbles: true }})); }} catch (_error) {{}} return ('value' in el ? el.value : el.textContent) === {value}; }})()",
            selector = quote_js(selector),
            value = quote_js(value)
        );

        match self.evaluate(page_id, script)? {
            NativeValue::Boolean(true) => Ok(()),
            NativeValue::Boolean(false) => Err("not_found".into()),
            other => Err(format!("unexpected_fill_result:{other:?}")),
        }
    }

    fn wait_for(&mut self, page_id: u64, selector: &str, timeout_ms: u64) -> Result<(), String> {
        let deadline = Instant::now() + Duration::from_millis(timeout_ms);

        loop {
            if self.selector_exists(page_id, selector)? {
                return Ok(());
            }

            if Instant::now() >= deadline {
                return Err("timeout".into());
            }

            self.spin_for(Duration::from_millis(25));
        }
    }

    fn hover(&mut self, page_id: u64, selector: &str) -> Result<(), String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;
        self.wait_for(page_id, selector, DEFAULT_TIMEOUT_MS)?;
        let point = self.selector_center(page_id, selector)?;

        webview.notify_input_event(InputEvent::MouseMove(MouseMoveEvent::new(point.into())));

        self.spin_for(Duration::from_millis(50));
        Ok(())
    }

    fn select_option(&mut self, page_id: u64, selector: &str, value: &str) -> Result<(), String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;
        self.wait_for(page_id, selector, DEFAULT_TIMEOUT_MS)?;

        let script = format!(
            "(() => {{ const el = document.querySelector({selector}); if (!el) return 'not_found'; if (!(el instanceof HTMLSelectElement)) return 'not_select'; const opt = Array.from(el.options).find(o => o.value === {value}); if (!opt) return 'option_not_found'; el.value = {value}; try {{ el.dispatchEvent(new Event('input', {{ bubbles: true }})); }} catch (_e) {{}} try {{ el.dispatchEvent(new Event('change', {{ bubbles: true }})); }} catch (_e) {{}} return 'ok'; }})()",
            selector = quote_js(selector),
            value = quote_js(value)
        );

        match self.evaluate(page_id, script)? {
            NativeValue::String(s) if s == "ok" => Ok(()),
            NativeValue::String(s) => Err(s),
            other => Err(format!("unexpected_select_result:{other:?}")),
        }
    }

    fn get_text(&mut self, page_id: u64, selector: &str) -> Result<String, String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;

        let script = format!(
            "(() => {{ const el = document.querySelector({selector}); if (!el) return null; return (el.innerText ?? el.textContent ?? '').trim(); }})()",
            selector = quote_js(selector)
        );

        match self.evaluate(page_id, script)? {
            NativeValue::String(s) => Ok(s),
            NativeValue::Null => Err("not_found".into()),
            other => Err(format!("unexpected_get_text_result:{other:?}")),
        }
    }

    fn get_attribute(&mut self, page_id: u64, selector: &str, name: &str) -> Result<NativeValue, String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;

        let script = format!(
            "(() => {{ const el = document.querySelector({selector}); if (!el) return {{ ok: false, error: 'not_found' }}; const v = el.getAttribute({name}); return {{ ok: true, value: v }}; }})()",
            selector = quote_js(selector),
            name = quote_js(name)
        );

        match self.evaluate(page_id, script)? {
            NativeValue::Object(map) => {
                match map.get("ok") {
                    Some(NativeValue::Boolean(true)) => {
                        Ok(map.get("value").cloned().unwrap_or(NativeValue::Null))
                    },
                    Some(NativeValue::Boolean(false)) => {
                        let error = match map.get("error") {
                            Some(NativeValue::String(s)) => s.clone(),
                            _ => "unknown".into(),
                        };
                        Err(error)
                    },
                    _ => Err("unexpected_get_attribute_result".into()),
                }
            },
            other => Err(format!("unexpected_get_attribute_result:{other:?}")),
        }
    }

    fn get_cookies(&mut self, page_id: u64) -> Result<NativeValue, String> {
        let script = "(() => { const raw = document.cookie; if (!raw || raw.length === 0) return []; return raw.split('; ').map(c => { const i = c.indexOf('='); return { name: i < 0 ? c : c.substring(0, i), value: i < 0 ? '' : c.substring(i + 1) }; }); })()".to_string();

        self.evaluate(page_id, script)
    }

    fn set_cookie(&mut self, page_id: u64, cookie_string: &str) -> Result<(), String> {
        let script = format!("document.cookie = {}", quote_js(cookie_string));

        match self.evaluate(page_id, script) {
            Ok(_) => Ok(()),
            Err(e) => Err(e),
        }
    }

    fn clear_cookies(&mut self, page_id: u64) -> Result<(), String> {
        let script = "(() => { document.cookie.split('; ').forEach(c => { const name = c.split('=')[0]; document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/'; }); })()".to_string();

        match self.evaluate(page_id, script) {
            Ok(_) => Ok(()),
            Err(e) => Err(e),
        }
    }

    fn close_page(&mut self, page_id: u64) -> Result<(), String> {
        self.webviews
            .remove(&page_id)
            .map(|_| ())
            .ok_or_else(|| "not_found".into())
    }

    fn selector_center(&mut self, page_id: u64, selector: &str) -> Result<DevicePoint, String> {
        let script = format!(
            "(() => {{ const el = document.querySelector({selector}); if (!el) return null; const rect = el.getBoundingClientRect(); return [rect.left + (rect.width / 2), rect.top + (rect.height / 2)]; }})()",
            selector = quote_js(selector)
        );

        match self.evaluate(page_id, script)? {
            NativeValue::Array(values) if values.len() == 2 => {
                let x = number_from_value(values.first()).ok_or_else(|| "invalid_x".to_string())?;
                let y = number_from_value(values.get(1)).ok_or_else(|| "invalid_y".to_string())?;
                Ok(DevicePoint::new(x as f32, y as f32))
            },
            NativeValue::Null => Err("not_found".into()),
            other => Err(format!("unexpected_selector_center:{other:?}")),
        }
    }

    fn page_state(&self, page_id: u64, webview: &WebView) -> PageState {
        PageState {
            id: page_id,
            title: webview.page_title().unwrap_or_default(),
            url: webview
                .url()
                .map(|url| url.to_string())
                .unwrap_or_else(|| "about:blank".into()),
        }
    }

    fn webview(&self, page_id: u64) -> Result<&WebView, String> {
        self.webviews.get(&page_id).ok_or_else(|| "not_found".into())
    }

    fn build_webview(&mut self, url: Url) -> Result<WebView, String> {
        let webview = WebViewBuilder::new(&self.servo, self.rendering_context.clone())
            .delegate(self.delegate.clone())
            .url(url)
            .build();

        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;
        Ok(webview)
    }

    fn take_screenshot_image(&mut self, page_id: u64) -> Result<RgbaImage, String> {
        let webview = self.webview(page_id)?.clone();
        self.wait_for_load(&webview, DEFAULT_TIMEOUT_MS)?;

        let stored = Rc::new(RefCell::new(None));
        let callback_stored = stored.clone();

        webview.take_screenshot(None, move |result| {
            *callback_stored.borrow_mut() = Some(result);
        });

        self.spin_until(DEFAULT_TIMEOUT_MS, || stored.borrow().is_none())?;

        let result = match stored.borrow_mut().take() {
            Some(Ok(image)) => Ok(image),
            Some(Err(error)) => Err(format!("{error:?}")),
            None => Err("screenshot_missing_result".into()),
        };

        result
    }

    fn wait_for_load(&mut self, webview: &WebView, timeout_ms: u64) -> Result<(), String> {
        self.spin_until(timeout_ms, || webview.load_status() != LoadStatus::Complete)
    }

    fn selector_exists(&mut self, page_id: u64, selector: &str) -> Result<bool, String> {
        let script = format!("(() => document.querySelector({}) !== null)()", quote_js(selector));

        match self.evaluate(page_id, script)? {
            NativeValue::Boolean(value) => Ok(value),
            other => Err(format!("unexpected_wait_result:{other:?}")),
        }
    }

    fn spin_until(
        &mut self,
        timeout_ms: u64,
        pending: impl Fn() -> bool,
    ) -> Result<(), String> {
        let deadline = Instant::now() + Duration::from_millis(timeout_ms);

        while pending() {
            self.servo.spin_event_loop();
            if Instant::now() >= deadline {
                return Err("timeout".into());
            }
            thread::sleep(Duration::from_millis(1));
        }

        Ok(())
    }

    fn spin_for(&mut self, duration: Duration) {
        let deadline = Instant::now() + duration;
        while Instant::now() < deadline {
            self.servo.spin_event_loop();
            thread::sleep(Duration::from_millis(1));
        }
    }
}

fn send_command<T>(
    sender: &Sender<Command>,
    build: impl FnOnce(Sender<Result<T, String>>) -> Command,
) -> NifResult<T> {
    let (reply_tx, reply_rx) = mpsc::channel();
    sender
        .send(build(reply_tx))
        .map_err(|error| Error::Term(Box::new(error.to_string())))?;
    reply_rx
        .recv()
        .map_err(|error| Error::Term(Box::new(error.to_string())))?
        .map_err(|error| Error::Term(Box::new(error)))
}

fn parse_url(input: &str) -> Result<Url, String> {
    Url::parse(input).map_err(|error| error.to_string())
}

fn page_attrs(page: PageState) -> PageAttrs {
    PageAttrs {
        id: page.id,
        title: page.title,
        url: page.url,
    }
}

fn native_value_from_js(value: JSValue) -> NativeValue {
    match value {
        JSValue::Undefined => NativeValue::Undefined,
        JSValue::Null => NativeValue::Null,
        JSValue::Boolean(value) => NativeValue::Boolean(value),
        JSValue::Number(value) => NativeValue::Number(value),
        JSValue::String(value)
        | JSValue::Element(value)
        | JSValue::ShadowRoot(value)
        | JSValue::Frame(value)
        | JSValue::Window(value) => NativeValue::String(value),
        JSValue::Array(values) => {
            NativeValue::Array(values.into_iter().map(native_value_from_js).collect())
        },
        JSValue::Object(values) => NativeValue::Object(
            values
                .into_iter()
                .map(|(key, value)| (key, native_value_from_js(value)))
                .collect(),
        ),
    }
}

fn encode_native_value<'a>(env: Env<'a>, value: &NativeValue) -> Term<'a> {
    match value {
        NativeValue::Undefined => atoms::undefined().encode(env),
        NativeValue::Null => ().encode(env),
        NativeValue::Boolean(value) => value.encode(env),
        NativeValue::Number(value) => value.encode(env),
        NativeValue::String(value) => value.encode(env),
        NativeValue::Array(values) => {
            let encoded: Vec<Term<'a>> = values
                .iter()
                .map(|value| encode_native_value(env, value))
                .collect();
            encoded.encode(env)
        },
        NativeValue::Object(values) => {
            let encoded: HashMap<String, Term<'a>> = values
                .iter()
                .map(|(key, value)| (key.clone(), encode_native_value(env, value)))
                .collect();
            encoded.encode(env)
        },
    }
}

fn encode_image(image: &RgbaImage, format: &str, quality: u8) -> Result<Vec<u8>, String> {
    let (width, height) = image.dimensions();
    let mut output = Vec::new();

    match format {
        "jpeg" | "jpg" => {
            let rgb = rgba_to_rgb(image.as_raw());
            let encoder = JpegEncoder::new_with_quality(&mut output, quality);
            encoder
                .write_image(&rgb, width, height, ColorType::Rgb8.into())
                .map_err(|error| error.to_string())?;
        },
        _ => {
            let encoder = PngEncoder::new(&mut output);
            encoder
                .write_image(image.as_raw(), width, height, ColorType::Rgba8.into())
                .map_err(|error| error.to_string())?;
        },
    }

    Ok(output)
}

fn rgba_to_rgb(rgba: &[u8]) -> Vec<u8> {
    let mut rgb = Vec::with_capacity((rgba.len() / 4) * 3);

    for chunk in rgba.chunks_exact(4) {
        rgb.extend_from_slice(&chunk[..3]);
    }

    rgb
}

fn render_pdf(image: &RgbaImage) -> Result<Vec<u8>, String> {
    let jpeg = encode_image(image, "jpeg", 90)?;
    let width = image.width();
    let height = image.height();
    let content = format!("q\n{width} 0 0 {height} 0 0 cm\n/Im0 Do\nQ\n");

    let objects = vec![
        br#"<< /Type /Catalog /Pages 2 0 R >>"#.to_vec(),
        br#"<< /Type /Pages /Count 1 /Kids [3 0 R] >>"#.to_vec(),
        format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] /Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>"
        )
        .into_bytes(),
        format!("<< /Length {} >>\nstream\n{}endstream", content.len(), content).into_bytes(),
        {
            let mut object = format!(
                "<< /Type /XObject /Subtype /Image /Width {width} /Height {height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {} >>\nstream\n",
                jpeg.len()
            )
            .into_bytes();
            object.extend_from_slice(&jpeg);
            object.extend_from_slice(b"\nendstream");
            object
        },
    ];

    build_pdf(objects)
}

fn build_pdf(objects: Vec<Vec<u8>>) -> Result<Vec<u8>, String> {
    let mut output = b"%PDF-1.4\n%\xFF\xFF\xFF\xFF\n".to_vec();
    let mut offsets = Vec::new();

    for (index, object) in objects.iter().enumerate() {
        offsets.push(output.len());
        output.extend_from_slice(format!("{} 0 obj\n", index + 1).as_bytes());
        output.extend_from_slice(object);
        output.extend_from_slice(b"\nendobj\n");
    }

    let xref_offset = output.len();
    output.extend_from_slice(format!("xref\n0 {}\n", objects.len() + 1).as_bytes());
    output.extend_from_slice(b"0000000000 65535 f \n");

    for offset in offsets {
        output.extend_from_slice(format!("{offset:010} 00000 n \n").as_bytes());
    }

    output.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF\n",
            objects.len() + 1,
            xref_offset
        )
        .as_bytes(),
    );

    Ok(output)
}

fn string_from_value(value: NativeValue) -> Result<String, String> {
    match value {
        NativeValue::String(value) => Ok(value),
        other => Err(format!("unexpected_string_value:{other:?}")),
    }
}

fn number_from_value(value: Option<&NativeValue>) -> Option<f64> {
    match value {
        Some(NativeValue::Number(value)) => Some(*value),
        _ => None,
    }
}

fn quote_js(value: &str) -> String {
    format!("{value:?}")
}

fn bytes_to_term<'a>(env: Env<'a>, bytes: &[u8]) -> Term<'a> {
    let mut binary = OwnedBinary::new(bytes.len()).expect("failed to allocate binary");
    binary.as_mut_slice().copy_from_slice(bytes);
    binary.release(env).encode(env)
}

fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(RuntimeResource, env);
    true
}

rustler::init!("Elixir.BrowseServo.Native", load = load);
