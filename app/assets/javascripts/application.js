(function () {
  function detectedTimeZone() {
    if (!window.Intl || !window.Intl.DateTimeFormat) return null;
    return window.Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  }

  function optionExists(field, value) {
    if (!field || field.tagName !== "SELECT") return true;
    return Array.prototype.some.call(field.options, function (option) {
      return option.value === value;
    });
  }

  function setFieldTimeZone(field, timeZone) {
    if (!timeZone || !field || !optionExists(field, timeZone)) return;
    field.value = timeZone;
    field.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function applyDetectedTimeZone() {
    var timeZone = detectedTimeZone();

    document.querySelectorAll("[data-time-zone-auto]").forEach(function (field) {
      setFieldTimeZone(field, timeZone);
    });

    document.querySelectorAll("[data-time-zone-detected-label]").forEach(function (display) {
      display.textContent = timeZone || display.dataset.fallbackTimeZone || "UTC";
    });

    document.querySelectorAll("[data-use-detected-time-zone]").forEach(function (button) {
      button.addEventListener("click", function () {
        var target = document.querySelector(button.dataset.useDetectedTimeZone);
        setFieldTimeZone(target, timeZone);
      });
    });

    document.querySelectorAll("[data-detected-time-zone-field]").forEach(function (field) {
      if (!timeZone) return;
      field.value = timeZone;
    });
  }

  function dismissFlashes() {
    document.querySelectorAll(".flash").forEach(function (flash) {
      if (flash.dataset.autoDismissBound === "true") return;
      flash.dataset.autoDismissBound = "true";

      window.setTimeout(function () {
        flash.classList.add("is-hiding");
        window.setTimeout(function () {
          flash.remove();
        }, 240);
      }, 2800);
    });
  }

  function pad(value) {
    return String(value).padStart(2, "0");
  }

  function datetimeLocalValue(date) {
    return [
      date.getFullYear(),
      "-",
      pad(date.getMonth() + 1),
      "-",
      pad(date.getDate()),
      "T",
      pad(date.getHours()),
      ":",
      pad(date.getMinutes())
    ].join("");
  }

  function syncSessionEndTime(source) {
    var grid = source.closest("[data-session-time-grid]");
    var targetSelector = source.dataset.endTimeTarget || (grid && grid.dataset.endTimeTarget);
    var target = document.querySelector(targetSelector);
    if (!target || !source.value) return;

    var duration = parseInt(source.dataset.durationMinutes || (grid && grid.dataset.durationMinutes) || "50", 10);
    var start = new Date(source.value);
    if (Number.isNaN(start.getTime())) return;

    start.setMinutes(start.getMinutes() + duration);
    target.value = datetimeLocalValue(start);
  }

  function bindSessionTimeSelects() {
    document.querySelectorAll("[data-session-start-select]").forEach(function (select) {
      if (select.dataset.sessionTimeBound === "true") return;
      select.dataset.sessionTimeBound = "true";
      select.addEventListener("change", function () {
        syncSessionEndTime(select);
      });
    });

    document.querySelectorAll("[data-session-start-option]").forEach(function (option) {
      if (option.dataset.sessionTimeBound === "true") return;
      option.dataset.sessionTimeBound = "true";
      option.addEventListener("change", function () {
        var grid = option.closest("[data-session-time-grid]");
        if (grid) {
          grid.querySelectorAll(".session-time-cell.selected").forEach(function (cell) {
            cell.classList.remove("selected");
            var label = cell.querySelector("span");
            if (label) label.textContent = grid.dataset.freeLabel || "Free";
          });
        }

        var cell = option.closest(".session-time-cell");
        if (cell) {
          cell.classList.add("selected");
          var selectedLabel = cell.querySelector("span");
          if (selectedLabel) selectedLabel.textContent = (grid && grid.dataset.selectedLabel) || "Selected";
        }

        syncSessionEndTime(option);
      });
    });
  }

  function setAvailabilityCell(cell, selected) {
    var input = cell.querySelector("[data-availability-cell]");
    if (!input) return;
    var grid = cell.closest("[data-availability-grid]");

    input.checked = selected;
    cell.classList.toggle("selected", selected);
    var label = cell.querySelector("span");
    if (label) label.textContent = selected ? ((grid && grid.dataset.availableLabel) || "Available") : ((grid && grid.dataset.closedLabel) || "Closed");
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function bindAvailabilityGrids() {
    document.querySelectorAll("[data-availability-grid]").forEach(function (grid) {
      if (grid.dataset.availabilityBound === "true") return;
      grid.dataset.availabilityBound = "true";

      var dragMode = null;

      grid.querySelectorAll(".availability-cell").forEach(function (cell) {
        var input = cell.querySelector("[data-availability-cell]");
        if (input) setAvailabilityCell(cell, input.checked);

        cell.addEventListener("mousedown", function (event) {
          event.preventDefault();
          var selected = !(input && input.checked);
          dragMode = selected;
          setAvailabilityCell(cell, selected);
        });

        cell.addEventListener("click", function (event) {
          event.preventDefault();
        });

        cell.addEventListener("mouseenter", function () {
          if (dragMode === null) return;
          setAvailabilityCell(cell, dragMode);
        });
      });

      window.addEventListener("mouseup", function () {
        dragMode = null;
      });
    });
  }

  function setAutosaveStatus(form, status, message) {
    var target = form.querySelector("[data-autosave-status]");
    if (!target) return;

    target.dataset.status = status;
    target.textContent = message;
  }

  function submitAutosaveForm(form) {
    if (form.dataset.autosaveSubmitting === "true") {
      form.dataset.autosaveQueued = "true";
      return;
    }

    form.dataset.autosaveSubmitting = "true";
    form.dataset.autosaveQueued = "false";
    setAutosaveStatus(form, "saving", "Saving...");

    window.fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      credentials: "same-origin",
      headers: {
        "X-Requested-With": "XMLHttpRequest"
      }
    }).then(function (response) {
      if (!response.ok) throw new Error("Autosave failed");
      setAutosaveStatus(form, "saved", "Saved");
    }).catch(function () {
      setAutosaveStatus(form, "error", "Could not save");
    }).finally(function () {
      form.dataset.autosaveSubmitting = "false";
      if (form.dataset.autosaveQueued === "true") {
        scheduleAutosave(form, 250);
      }
    });
  }

  function scheduleAutosave(form, delay) {
    window.clearTimeout(form._autosaveTimer);
    setAutosaveStatus(form, "pending", "Unsaved changes");
    form._autosaveTimer = window.setTimeout(function () {
      submitAutosaveForm(form);
    }, delay);
  }

  function bindSettingsAutosave() {
    document.querySelectorAll("[data-settings-autosave]").forEach(function (form) {
      if (form.dataset.autosaveBound === "true") return;
      form.dataset.autosaveBound = "true";

      form.addEventListener("input", function (event) {
        if (event.target.matches("[data-availability-cell]")) return;
        scheduleAutosave(form, 700);
      });

      form.addEventListener("change", function () {
        scheduleAutosave(form, 350);
      });

      form.addEventListener("submit", function (event) {
        event.preventDefault();
        submitAutosaveForm(form);
      });
    });
  }

  function bindDismissibleDetails() {
    if (document.body.dataset.dismissibleDetailsBound === "true") return;
    document.body.dataset.dismissibleDetailsBound = "true";

    document.addEventListener("click", function (event) {
      document.querySelectorAll("details[open].profile-menu, details[open].agenda-block-menu").forEach(function (details) {
        if (details.contains(event.target)) return;
        details.removeAttribute("open");
      });
    });
  }

  document.addEventListener("DOMContentLoaded", applyDetectedTimeZone);
  document.addEventListener("DOMContentLoaded", dismissFlashes);
  document.addEventListener("DOMContentLoaded", bindSessionTimeSelects);
  document.addEventListener("DOMContentLoaded", bindAvailabilityGrids);
  document.addEventListener("DOMContentLoaded", bindSettingsAutosave);
  document.addEventListener("DOMContentLoaded", bindDismissibleDetails);
  document.addEventListener("turbo:load", function () {
    applyDetectedTimeZone();
    dismissFlashes();
    bindSessionTimeSelects();
    bindAvailabilityGrids();
    bindSettingsAutosave();
    bindDismissibleDetails();
  });
})();
