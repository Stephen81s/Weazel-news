const resourceName = typeof GetParentResourceName === "function" ? GetParentResourceName() : "weazel_news";
const body = document.body;
const importView = document.getElementById("importView");
const readerView = document.getElementById("readerView");

let selectedImport = null;
let readerZoom = 1;

const importPage = {
  fileInput: document.getElementById("journalFile"),
  preview: document.getElementById("importPreview"),
  fileName: document.getElementById("fileName"),
  fileResolution: document.getElementById("fileResolution"),
  publishButton: document.getElementById("publishButton"),
  closeButton: document.getElementById("closeImportButton"),
  status: document.getElementById("importStatus"),
  maxFileSize: document.getElementById("maxFileSize"),
  recommendedResolution: document.getElementById("recommendedResolution"),
};

const readerPage = {
  title: document.getElementById("readerTitle"),
  meta: document.getElementById("readerMeta"),
  image: document.getElementById("readerImage"),
  viewport: document.getElementById("readerViewport"),
  zoomIn: document.getElementById("zoomInButton"),
  zoomOut: document.getElementById("zoomOutButton"),
  closeButton: document.getElementById("closeReaderButton"),
};

function nuiPost(endpoint, payload = {}) {
  return fetch(`https://${resourceName}/${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify(payload),
  });
}

function setStatus(message, isError = false) {
  if (!importPage.status) return;
  importPage.status.textContent = message;
  importPage.status.classList.toggle("error", isError);
}

function closePage() {
  body.classList.add("page-hidden");
  importView?.classList.add("page-hidden");
  readerView?.classList.add("page-hidden");
  selectedImport = null;
}

function openImportPage(payload) {
  body.classList.remove("page-hidden");
  importView?.classList.remove("page-hidden");
  readerView?.classList.add("page-hidden");

  if (importPage.maxFileSize) {
    importPage.maxFileSize.textContent = `${payload.maxFileSizeMB ?? 5} MB`;
  }

  if (importPage.recommendedResolution) {
    importPage.recommendedResolution.textContent = payload.recommendedResolution ?? "1080x1920";
  }

  if (importPage.preview) {
    importPage.preview.removeAttribute("src");
    importPage.preview.style.display = "none";
  }

  if (importPage.publishButton) {
    importPage.publishButton.disabled = true;
  }

  if (importPage.fileName) importPage.fileName.textContent = "Aucun fichier selectionne.";
  if (importPage.fileResolution) importPage.fileResolution.textContent = "Resolution : inconnue";
  setStatus("Selectionnez un PNG ou un JPG puis attendez la validation serveur.");
}

function openReaderPage(payload) {
  body.classList.remove("page-hidden");
  readerView?.classList.remove("page-hidden");
  importView?.classList.add("page-hidden");
  readerZoom = 1;

  if (!payload?.journal || !readerPage.image) return;

  const journal = payload.journal;
  readerPage.title.textContent = journal.filename || "Weazel News";
  readerPage.meta.textContent = `Par ${journal.author || "inconnu"} | ${journal.publishDate || "date inconnue"} | ${journal.resolution || "resolution inconnue"}`;
  readerPage.image.src = journal.imageUrl;
  readerPage.image.style.display = "block";
  readerPage.image.style.transform = "scale(1)";
  readerPage.viewport.scrollTop = 0;
  readerPage.viewport.scrollLeft = 0;
}

async function fileToDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error("read_failed"));
    reader.readAsDataURL(file);
  });
}

async function getImageResolution(dataUrl) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(`${image.width}x${image.height}`);
    image.onerror = () => reject(new Error("image_failed"));
    image.src = dataUrl;
  });
}

if (importPage.fileInput) {
  importPage.fileInput.addEventListener("change", async (event) => {
    const file = event.target.files?.[0];

    if (!file) {
      return;
    }

    try {
      setStatus("Lecture du fichier en cours...");
      const dataUrl = await fileToDataUrl(file);
      const resolution = await getImageResolution(dataUrl);

      selectedImport = {
        filename: file.name,
        mimeType: file.type,
        size: file.size,
        resolution,
        dataUrl,
      };

      importPage.fileName.textContent = `Fichier : ${file.name}`;
      importPage.fileResolution.textContent = `Resolution : ${resolution}`;
      importPage.preview.src = dataUrl;
      importPage.preview.style.display = "block";
      importPage.publishButton.disabled = true;
      setStatus("Validation serveur en cours...");

      await nuiPost("validateImport", selectedImport);
    } catch (error) {
      setStatus("Impossible de lire ce fichier.", true);
    }
  });
}

if (importPage.publishButton) {
  importPage.publishButton.addEventListener("click", async () => {
    importPage.publishButton.disabled = true;
    setStatus("Publication en cours...");
    await nuiPost("publishJournal", {});
  });
}

if (importPage.closeButton) {
  importPage.closeButton.addEventListener("click", async () => {
    await nuiPost("close", {});
  });
}

if (readerPage.closeButton) {
  readerPage.closeButton.addEventListener("click", async () => {
    await nuiPost("close", {});
  });
}

if (readerPage.zoomIn) {
  readerPage.zoomIn.addEventListener("click", () => {
    readerZoom = Math.min(readerZoom + 0.15, 3);
    readerPage.image.style.transform = `scale(${readerZoom})`;
  });
}

if (readerPage.zoomOut) {
  readerPage.zoomOut.addEventListener("click", () => {
    readerZoom = Math.max(readerZoom - 0.15, 0.4);
    readerPage.image.style.transform = `scale(${readerZoom})`;
  });
}

window.addEventListener("message", (event) => {
  const { action, page, payload } = event.data ?? {};

  if (action === "closePage") {
    closePage();
    return;
  }

  if (action === "openPage") {
    if (page === "import") {
      openImportPage(payload ?? {});
    }

    if (page === "reader") {
      openReaderPage(payload ?? {});
    }
  }

  if (action === "importValidated") {
    selectedImport = payload ?? selectedImport;
    importPage.publishButton.disabled = false;
    setStatus(`Fichier valide : ${payload.filename} (${payload.resolution}).`);
  }
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    nuiPost("close", {});
  }
});
