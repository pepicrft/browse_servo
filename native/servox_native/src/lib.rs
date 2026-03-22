#![allow(non_local_definitions)]

use rustler::{Atom, Encoder, Env, Error, NifMap, NifResult, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::RwLock;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        servox,
        rustler,
        planned,
        direct,
        not_found,
        unsupported
    }
}

#[derive(Default)]
struct RuntimeResource {
    next_page_id: AtomicU64,
    pages: RwLock<HashMap<u64, PageState>>,
}

#[derive(Clone)]
struct PageState {
    title: String,
    url: String,
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

#[rustler::nif]
fn new_runtime() -> NifResult<(Atom, ResourceArc<RuntimeResource>)> {
    Ok((atoms::ok(), ResourceArc::new(RuntimeResource::default())))
}

#[rustler::nif]
fn shutdown(_runtime: ResourceArc<RuntimeResource>) -> Atom {
    atoms::ok()
}

#[rustler::nif]
fn capabilities<'a>(
    env: Env<'a>,
    _runtime: ResourceArc<RuntimeResource>,
) -> NifResult<(Atom, Term<'a>)> {
    let capabilities = Capabilities {
        engine: atoms::servox(),
        embedding: atoms::rustler(),
        javascript: atoms::planned(),
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
    let id = runtime.next_page_id.fetch_add(1, Ordering::SeqCst) + 1;
    let page = page_state_for_url(url);

    runtime
        .pages
        .write()
        .map_err(|_| Error::Term(Box::new("lock error")))?
        .insert(id, page.clone());

    Ok((atoms::ok(), page_map(env, id, &page)?.encode(env)))
}

#[rustler::nif]
fn navigate<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    url: String,
) -> NifResult<(Atom, Term<'a>)> {
    let page = page_state_for_url(url);

    runtime
        .pages
        .write()
        .map_err(|_| Error::Term(Box::new("lock error")))?
        .insert(page_id, page.clone());

    Ok((atoms::ok(), page_map(env, page_id, &page)?.encode(env)))
}

#[rustler::nif]
fn content(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<(Atom, String)> {
    let page = find_page(&runtime, page_id)?;
    Ok((atoms::ok(), html_for_page(&page)))
}

#[rustler::nif]
fn title(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<(Atom, String)> {
    let page = find_page(&runtime, page_id)?;
    Ok((atoms::ok(), page.title))
}

#[rustler::nif]
fn evaluate<'a>(
    env: Env<'a>,
    runtime: ResourceArc<RuntimeResource>,
    page_id: u64,
    expression: String,
) -> NifResult<(Atom, Term<'a>)> {
    let page = find_page(&runtime, page_id)?;

    let value = match expression.as_str() {
        "document.title" => page.title.encode(env),
        "document.location.href" => page.url.encode(env),
        "document.body.innerHTML" => format!("<main data-url=\"{}\"></main>", page.url).encode(env),
        _ => atoms::ok().encode(env),
    };

    Ok((atoms::ok(), value))
}

#[rustler::nif]
fn capture_screenshot(
    _runtime: ResourceArc<RuntimeResource>,
    _page_id: u64,
    _format: String,
    _quality: u8,
) -> NifResult<(Atom, Atom)> {
    Ok((atoms::error(), atoms::unsupported()))
}

#[rustler::nif]
fn close_page(runtime: ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<Atom> {
    runtime
        .pages
        .write()
        .map_err(|_| Error::Term(Box::new("lock error")))?
        .remove(&page_id);

    Ok(atoms::ok())
}

fn page_state_for_url(url: String) -> PageState {
    PageState {
        title: format!("Page for {}", url),
        url,
    }
}

fn page_map<'a>(env: Env<'a>, id: u64, page: &PageState) -> NifResult<Term<'a>> {
    Ok(PageAttrs {
        id,
        title: page.title.clone(),
        url: page.url.clone(),
    }
    .encode(env))
}

fn html_for_page(page: &PageState) -> String {
    format!(
        "<html><head><title>{}</title></head><body><main data-url=\"{}\"></main></body></html>",
        page.title, page.url
    )
}

fn find_page(runtime: &ResourceArc<RuntimeResource>, page_id: u64) -> NifResult<PageState> {
    runtime
        .pages
        .read()
        .map_err(|_| Error::Term(Box::new("lock error")))?
        .get(&page_id)
        .cloned()
        .ok_or_else(|| Error::Term(Box::new(atoms::not_found())))
}

fn load(env: Env, _info: Term) -> bool {
    let _ = rustler::resource!(RuntimeResource, env);
    true
}

rustler::init!("Elixir.Servox.Native", load = load);
