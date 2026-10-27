import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import { DISCLAIMER, localDay } from "./domain.js";
export async function makeHistoryPdf(state, doses, range) {
  const doc = await PDFDocument.create();
  doc.setTitle("PillCheck · Synthetic medication history");
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const safe = (value) => String(value ?? "").replace(/[^\x20-\x7E\n]/g, "?");
  let page, y;
  const newPage = () => {
    page = doc.addPage([595.28, 841.89]);
    y = 785;
    page.drawText("PILLCHECK | SYNTHETIC DEMO RECORD", {
      x: 42,
      y,
      font: bold,
      size: 10,
      color: rgb(0.15, 0.38, 0.29),
    });
    y -= 36;
  };
  const line = (text, size = 10, weight = font) => {
    if (y < 62) newPage();
    page.drawText(safe(text), {
      x: 42,
      y,
      font: weight,
      size,
      color: rgb(0.15, 0.19, 0.17),
    });
    y -= size + 8;
  };
  const wrap = (text, size = 10, weight = font) => {
    let row = "";
    for (const word of safe(text).split(/\s+/)) {
      const next = row ? `${row} ${word}` : word;
      if (weight.widthOfTextAtSize(next, size) > 505 && row) {
        line(row, size, weight);
        row = word;
      } else row = next;
    }
    if (row) line(row, size, weight);
  };
  newPage();
  line("Medication history", 23, bold);
  wrap(state.patient, 12, bold);
  wrap(`Generated: ${new Date().toLocaleString()}`);
  wrap(`Period: ${range.from} to ${range.to}`);
  wrap("All records in this document are fictional demonstration data.");
  wrap(DISCLAIMER);
  y -= 14;
  line("Medication and regimen archive", 15, bold);
  for (const m of state.medications) {
    if (y < 160) newPage();
    wrap(`${m.name} | ${m.strengthMg} mg`, 12, bold);
    wrap(
      `Active ingredient: ${m.ingredient}. Dose: ${m.doseQuantity} ${m.doseUnit}(s). Recorded times: ${m.times.join(", ")}.`,
    );
    wrap(
      `Start: ${m.startDate}. End: ${m.endDate || "ongoing"}. Status: ${m.status}.`,
    );
    y -= 8;
  }
  line("Daily dose log", 15, bold);
  for (const d of [...doses].sort((a, b) =>
    a.scheduledAt.localeCompare(b.scheduledAt),
  )) {
    if (y < 110) newPage();
    const m = state.medications.find((m) => m.id === d.medicationId);
    wrap(
      `${localDay(d.scheduledAt)} ${new Date(d.scheduledAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} | ${m?.name || "Archived medication"} | ${d.status.replaceAll("_", " ")}`,
      10,
      bold,
    );
    if (d.confirmedAt)
      wrap(
        `Recorded: ${new Date(d.confirmedAt).toLocaleString()} (${d.method}).`,
      );
    if (d.reason) wrap(`Note: ${d.reason}`);
    if (d.replanReason) wrap(`Timing change: ${d.replanReason}`);
    y -= 4;
  }
  if (state.changes.length) {
    line("Timing change audit", 15, bold);
    for (const change of state.changes) {
      wrap(
        `${new Date(change.at).toLocaleString()} | ${change.oldTime} -> ${change.newTime}`,
      );
      wrap(change.reason);
    }
  }
  doc
    .getPages()
    .forEach((p, i) =>
      p.drawText(
        `PillCheck | Fictional data | Page ${i + 1} of ${doc.getPageCount()}`,
        { x: 42, y: 28, size: 9, font, color: rgb(0.4, 0.45, 0.42) },
      ),
    );
  return await doc.save();
}
export function downloadFile(bytes, name, type) {
  const blob = new Blob([bytes], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
