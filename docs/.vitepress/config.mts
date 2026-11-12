import { defineConfig } from 'vitepress'

const repositoryUrl = 'https://github.com/Hybrid-Solutions-Cloud/wagonmaster'
const base = '/wagonmaster/'

// ---------------------------------------------------------------------------
// Sidebar building blocks
//
// Wagonmaster is a family of tools. Each tool owns one folder under docs/ and
// one sidebar array here. To add a tool: create docs/<tool>/, add its sidebar
// array, register it in `sidebar` below, and add it to the Tools menu in `nav`.
// ---------------------------------------------------------------------------

const manifestSidebar = [
  {
    text: 'Wagonmaster Manifest',
    items: [
      { text: 'Overview', link: '/manifest/' },
      { text: 'How to use', link: '/manifest/usage' },
      { text: 'Security and access', link: '/manifest/security' },
      { text: 'API reference', link: '/manifest/api-reference' },
    ],
  },
  {
    text: 'Downloads',
    collapsed: true,
    items: [
      { text: 'How to use (Word)', link: '/downloads/wagonmaster-manifest-usage.docx', target: '_self' },
      { text: 'Security and access (Word)', link: '/downloads/wagonmaster-manifest-security.docx', target: '_self' },
      { text: 'API reference (Word)', link: '/downloads/wagonmaster-manifest-api-reference.docx', target: '_self' },
    ],
  },
]

const projectSidebar = [
  {
    text: 'Project',
    items: [
      { text: 'About', link: '/project/about' },
      { text: 'Roadmap', link: '/project/roadmap' },
      { text: 'Changelog', link: '/project/changelog' },
      { text: 'License', link: '/project/license' },
    ],
  },
]

export default defineConfig({
  base,
  title: 'Wagonmaster',
  description: 'Open tools for Azure migrations, starting with a full data export of an Azure Migrate project.',
  lang: 'en-US',
  cleanUrls: true,
  lastUpdated: true,

  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}favicon.svg` }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: `${base}favicon-32x32.png` }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: `${base}favicon-16x16.png` }],
    ['link', { rel: 'shortcut icon', href: `${base}favicon.ico` }],
    ['link', { rel: 'apple-touch-icon', sizes: '180x180', href: `${base}apple-touch-icon.png` }],
    ['link', { rel: 'manifest', href: `${base}site.webmanifest` }],
    ['meta', { name: 'theme-color', content: '#0b2a4a' }],
  ],

  sitemap: {
    hostname: 'https://labs.hybridsolutions.cloud/wagonmaster/',
  },

  themeConfig: {
    logo: {
      src: '/assets/images/wagonmaster-icon.svg',
      alt: 'Wagonmaster',
    },
    siteTitle: 'Wagonmaster',

    nav: [
      { text: 'Home', link: '/' },
      { text: 'Start here', link: '/start-here' },
      {
        text: 'Tools',
        items: [
          { text: 'Manifest: project data export', link: '/manifest/' },
          { text: 'Planned tools', link: '/project/roadmap' },
        ],
      },
      { text: 'Project', link: '/project/about' },
    ],

    sidebar: {
      '/manifest/': manifestSidebar,
      '/project/': projectSidebar,
    },

    search: {
      provider: 'local',
    },

    outline: {
      level: [2, 3],
    },

    editLink: {
      pattern: `${repositoryUrl}/edit/main/docs/:path`,
      text: 'Edit this page on GitHub',
    },

    lastUpdated: {
      text: 'Last updated',
    },

    docFooter: {
      prev: 'Previous page',
      next: 'Next page',
    },

    socialLinks: [
      { icon: 'github', link: repositoryUrl },
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © Hybrid Solutions Cloud contributors',
    },
  },
})
