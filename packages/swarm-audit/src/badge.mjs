export function badgeColor(rate) {
  if (rate < 0.1) return '#3B6D11';
  if (rate < 0.25) return '#BA7517';
  return '#A32D2D';
}

export function renderBadge(rate) {
  const label = 'coordination incidents';
  const value = `${Math.round(rate * 100)}%`;
  const lw = label.length * 6.2 + 12;
  const vw = value.length * 7 + 12;
  const w = lw + vw;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="20" role="img" aria-label="${label}: ${value}"><title>${label}: ${value}</title><rect width="${lw}" height="20" fill="#555"/><rect x="${lw}" width="${vw}" height="20" fill="${badgeColor(rate)}"/><g fill="#fff" font-family="Verdana,DejaVu Sans,sans-serif" font-size="11" text-anchor="middle"><text x="${lw / 2}" y="14">${label}</text><text x="${lw + vw / 2}" y="14">${value}</text></g></svg>`;
}
