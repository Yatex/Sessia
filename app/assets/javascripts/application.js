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

  function parseLocalDate(value) {
    var date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function setSessionBlockCell(cell, selected, grid) {
    var input = cell.querySelector("[data-session-block-option]");
    if (!input) return;

    input.checked = selected;
    cell.classList.toggle("selected", selected);
    var label = cell.querySelector("span");
    if (label) label.textContent = selected ? (grid.dataset.selectedLabel || "Selected") : (grid.dataset.freeLabel || "Free");
  }

  function cellsForSessionDay(grid, dayKey) {
    return Array.prototype.slice.call(grid.querySelectorAll("[data-session-block-option]"))
      .filter(function (input) { return input.dataset.dayKey === dayKey; })
      .map(function (input) { return input.closest(".session-time-cell"); })
      .filter(Boolean)
      .sort(function (a, b) {
        return a.querySelector("[data-session-block-option]").dataset.startTime.localeCompare(
          b.querySelector("[data-session-block-option]").dataset.startTime
        );
      });
  }

  function selectionHasThirtyMinuteContinuity(cells) {
    for (var index = 1; index < cells.length; index += 1) {
      var previous = parseLocalDate(cells[index - 1].querySelector("[data-session-block-option]").dataset.startTime);
      var current = parseLocalDate(cells[index].querySelector("[data-session-block-option]").dataset.startTime);
      if (!previous || !current) return false;
      if ((current.getTime() - previous.getTime()) !== 30 * 60 * 1000) return false;
    }

    return true;
  }

  function syncSessionBlockSelection(changedInput) {
    var grid = changedInput.closest("[data-session-time-grid]");
    if (!grid) return;

    var dayKey = changedInput.dataset.dayKey;
    var sameDayCells = cellsForSessionDay(grid, dayKey);

    grid.querySelectorAll("[data-session-block-option]").forEach(function (input) {
      if (input.dataset.dayKey !== dayKey) setSessionBlockCell(input.closest(".session-time-cell"), false, grid);
    });

    var selectedCells = sameDayCells.filter(function (cell) {
      return cell.querySelector("[data-session-block-option]").checked;
    });

    if (selectedCells.length === 0) {
      setSessionBlockCell(changedInput.closest(".session-time-cell"), true, grid);
      selectedCells = [changedInput.closest(".session-time-cell")];
    }

    var selectedStarts = selectedCells.map(function (cell) {
      return cell.querySelector("[data-session-block-option]").dataset.startTime;
    }).sort();
    var firstStart = selectedStarts[0];
    var lastStart = selectedStarts[selectedStarts.length - 1];

    var rangeCells = sameDayCells.filter(function (cell) {
      var start = cell.querySelector("[data-session-block-option]").dataset.startTime;
      return start >= firstStart && start <= lastStart;
    });

    if (!selectionHasThirtyMinuteContinuity(rangeCells)) {
      rangeCells = [changedInput.closest(".session-time-cell")];
    }

    sameDayCells.forEach(function (cell) {
      setSessionBlockCell(cell, rangeCells.indexOf(cell) >= 0, grid);
    });

    var selectedRange = rangeCells.sort(function (a, b) {
      return a.querySelector("[data-session-block-option]").dataset.startTime.localeCompare(
        b.querySelector("[data-session-block-option]").dataset.startTime
      );
    });
    var firstInput = selectedRange[0] && selectedRange[0].querySelector("[data-session-block-option]");
    var lastInput = selectedRange[selectedRange.length - 1] && selectedRange[selectedRange.length - 1].querySelector("[data-session-block-option]");
    var startTarget = document.querySelector(grid.dataset.startTimeTarget);
    var endTarget = document.querySelector(grid.dataset.endTimeTarget);

    if (startTarget && firstInput) startTarget.value = firstInput.dataset.startTime;
    if (endTarget && lastInput) endTarget.value = lastInput.dataset.endTime;
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

    document.querySelectorAll("[data-session-block-option]").forEach(function (option) {
      if (option.dataset.sessionBlockBound === "true") return;
      option.dataset.sessionBlockBound = "true";

      var grid = option.closest("[data-session-time-grid]");
      var cell = option.closest(".session-time-cell");
      if (grid && cell) setSessionBlockCell(cell, option.checked, grid);

      option.addEventListener("change", function () {
        syncSessionBlockSelection(option);
      });
    });
  }

  function bindRecurrenceCheckboxes() {
    document.querySelectorAll("[data-recurrence-checkbox]").forEach(function (checkbox) {
      if (checkbox.dataset.recurrenceBound === "true") return;
      checkbox.dataset.recurrenceBound = "true";

      var form = checkbox.closest("form");
      var field = form && form.querySelector("[data-recurrence-frequency-field]");
      var sync = function () {
        if (field) field.value = checkbox.checked ? "weekly" : "none";
      };

      sync();
      checkbox.addEventListener("change", sync);
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
  document.addEventListener("DOMContentLoaded", bindRecurrenceCheckboxes);
  document.addEventListener("DOMContentLoaded", bindAvailabilityGrids);
  document.addEventListener("DOMContentLoaded", bindSettingsAutosave);
  document.addEventListener("DOMContentLoaded", bindDismissibleDetails);
  document.addEventListener("turbo:load", function () {
    applyDetectedTimeZone();
    dismissFlashes();
    bindSessionTimeSelects();
    bindRecurrenceCheckboxes();
    bindAvailabilityGrids();
    bindSettingsAutosave();
    bindDismissibleDetails();
  });
})();
