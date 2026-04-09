# App Patterns Reference

Common patterns, snippets, and CDN libraries for DAME apps.

## DAME Brand

```css
:root {
  --dame-blue:   #1B4B8A;
  --dame-orange: #F5A623;
  --dame-dark:   #1a1a2e;
  --dame-light:  #f4f6f9;
  --text:        #333;
}
```

## CDN Libraries (no build step needed)

| Library | CDN | Use for |
|---|---|---|
| Chart.js | `https://cdn.jsdelivr.net/npm/chart.js` | Bar, line, pie, doughnut charts |
| Plotly.js | `https://cdn.plot.ly/plotly-2.35.2.min.js` | Interactive charts, time series |
| Tailwind CSS | `https://cdn.tailwindcss.com` | Styling |
| Alpine.js | `https://cdn.jsdelivr.net/npm/alpinejs@3/dist/cdn.min.js` | Lightweight reactivity |
| DataTables | `https://cdn.datatables.net/1.13.6/js/jquery.dataTables.min.js` | Sortable/filterable tables |
| Leaflet | `https://unpkg.com/leaflet/dist/leaflet.js` | Maps |
| Papa Parse | `https://cdn.jsdelivr.net/npm/papaparse@5/papaparse.min.js` | Parse CSV data in-browser |

## Pattern 1: Chart Dashboard (Chart.js)

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Dashboard — DAME</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body class="bg-gray-50 font-sans">
  <header class="bg-[#1B4B8A] text-white px-6 py-4">
    <h1 class="text-xl font-semibold">My Dashboard</h1>
  </header>
  <main class="p-6 max-w-5xl mx-auto">
    <div class="bg-white rounded shadow p-4">
      <canvas id="myChart" height="80"></canvas>
    </div>
  </main>
  <script>
    const ctx = document.getElementById('myChart');
    new Chart(ctx, {
      type: 'line',
      data: {
        labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May'],
        datasets: [{
          label: 'Value',
          data: [12, 19, 8, 15, 22],
          borderColor: '#1B4B8A',
          backgroundColor: 'rgba(27, 75, 138, 0.1)',
          tension: 0.3,
          fill: true,
        }]
      },
      options: { responsive: true, plugins: { legend: { position: 'top' } } }
    });
  </script>
</body>
</html>
```

## Pattern 2: Data Table

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Report — DAME</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-50 font-sans">
  <header class="bg-[#1B4B8A] text-white px-6 py-4">
    <h1 class="text-xl font-semibold">Report Title</h1>
    <p class="text-sm opacity-75" id="updated"></p>
  </header>
  <main class="p-6 max-w-6xl mx-auto">
    <div class="bg-white rounded shadow overflow-x-auto">
      <table class="w-full text-sm">
        <thead class="bg-gray-100 text-left">
          <tr>
            <th class="px-4 py-3 font-medium">Column A</th>
            <th class="px-4 py-3 font-medium">Column B</th>
            <th class="px-4 py-3 font-medium text-right">Value</th>
          </tr>
        </thead>
        <tbody id="tbody" class="divide-y divide-gray-100"></tbody>
      </table>
    </div>
  </main>
  <script>
    document.getElementById('updated').textContent = 'Updated: ' + new Date().toLocaleString('en-AU');
    const rows = [
      { a: 'Item 1', b: 'Category X', v: 42 },
      { a: 'Item 2', b: 'Category Y', v: 17 },
    ];
    const tbody = document.getElementById('tbody');
    rows.forEach(r => {
      tbody.innerHTML += `<tr class="hover:bg-gray-50">
        <td class="px-4 py-3">${r.a}</td>
        <td class="px-4 py-3">${r.b}</td>
        <td class="px-4 py-3 text-right font-mono">${r.v}</td>
      </tr>`;
    });
  </script>
</body>
</html>
```

## Pattern 3: Stat Cards + Chart

```html
<!-- Stat card component -->
<div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
  <div class="bg-white rounded shadow p-4">
    <p class="text-xs text-gray-500 uppercase tracking-wide">Total</p>
    <p class="text-2xl font-bold text-[#1B4B8A]">1,234</p>
    <p class="text-xs text-green-600 mt-1">↑ 12% vs last month</p>
  </div>
  <!-- repeat for other stats -->
</div>
```

## Pattern 4: Fetch data from an API or JSON file

```javascript
// Fetch from a JSON file hosted in the same S3 folder
fetch('./data.json')
  .then(r => r.json())
  .then(data => {
    // render data
  });

// Or fetch from an external API (must support CORS)
fetch('https://api.example.com/data')
  .then(r => r.json())
  .then(data => { /* ... */ });
```

## Pattern 5: Auto-refresh dashboard

```javascript
// Refresh every 5 minutes
setInterval(() => location.reload(), 5 * 60 * 1000);

// Or just re-fetch data without full reload
async function refresh() {
  const data = await fetch('./data.json').then(r => r.json());
  renderCharts(data);
}
setInterval(refresh, 5 * 60 * 1000);
```

## Multi-file app structure

For more complex apps with multiple files:

```
my-app/
├── index.html       # entry point (required)
├── style.css
├── app.js
└── data.json        # static data file (optional)
```

Upload all files — the deploy script syncs the entire directory.
