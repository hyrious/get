let db: { id: string, kw: string[], url: string, src: 'scoop' | 'winget' }[] | undefined;

const CHUNK = 20
let current = 0, maxsize = CHUNK;

const $: typeof document.querySelector = (sel: string) => document.querySelector(sel)

const $winget: HTMLInputElement = $('#winget')
const $scoop: HTMLInputElement = $('#scoop')
const $search: HTMLInputElement = $('#search')
const $result = $('#result')
const $template: HTMLTemplateElement = $('#result-item-template')
const $more: HTMLButtonElement = $('#more')

customElements.define('result-item', class extends HTMLElement {
  constructor() {
    super()
    this.attachShadow({ mode: 'open' })
        .append($template.content.cloneNode(true))
  }
})

let raf = 0, cursor = 0;

function reset() {
  current = cursor = 0
  maxsize = CHUNK
  $result.innerHTML = ''
  $more.disabled = true
}

function h(tag: string, attrs: object) {
  return Object.assign(document.createElement(tag), attrs);
}

async function refresh() {
  if (current < maxsize) {
    current += CHUNK
    raf = requestAnimationFrame(refresh)
  }

  let i = 0
  const winget = $winget.checked, scoop = $scoop.checked
  const hint = $search.value.toLowerCase().split(/\s+/)
  while (cursor < db.length && i < CHUNK) {
    let { id, kw, url, src } = db[cursor++]
    if (src === "scoop" && !scoop) continue;
    if (src === "winget" && !winget) continue;
    if (hint.some(k => kw.some(e => e.toLowerCase().includes(k)))) {
      let dom = document.createElement('result-item')
      dom.append(
        h('span', { slot: 'id', textContent: id }),
        h('span', { slot: 'kw', textContent: kw.join(',') }),
        h('span', { slot: 'src', textContent: src }),
        h('a', { slot: 'url', textContent: url, href: url }),
      )
      $result.append(dom)
      i++
    }
  }

  $more.disabled = !(cursor < db.length)
}

function search() {
  reset()
  cancelAnimationFrame(raf)
  raf = requestAnimationFrame(refresh)
}

function more() {
  maxsize += CHUNK
  raf = requestAnimationFrame(refresh)
}

async function main() {
  $search.disabled = true

  db = await fetch("db.json").then(r => r.json())

  $search.disabled = false
  $search.placeholder = "search here"
  $search.focus()

  $search.addEventListener('input', search)

  $more.addEventListener('click', more)
  $winget.addEventListener('change', search)
  $scoop.addEventListener('change', search)
}

main()

if (import.meta.env.DEV)
  navigator.serviceWorker?.getRegistrations().then(r => {
    r.forEach(e => e.unregister())
  })
