import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="import"
export default class extends Controller {
  static values = {
    csv: { type: Array, default: [] },
    amountTypeColumnKey: { type: String, default: "" },
  };

  static targets = [
    "signedAmountFieldset",
    "customColumnFieldset",
    "amountTypeValue",
    "amountTypeInflowValue",
    "amountTypeStrategySelect",
    "splitColumnsFieldset",
    "amountColumn",
  ];

  connect() {
    if (
      this.amountTypeStrategySelectTarget.value === "custom_column" &&
      this.amountTypeColumnKeyValue
    ) {
      this.#showAmountTypeValueTargets(this.amountTypeColumnKeyValue);
      if (this.amountTypeValueTarget.querySelector("select")?.value) {
        this.#showAmountTypeInflowValueTargets();
      }
    }
  }

  handleAmountTypeStrategyChange(event) {
    const amountTypeStrategy = event.target.value;

    this.#toggleSplitColumns(amountTypeStrategy === "split_columns");

    if (amountTypeStrategy === "custom_column") {
      this.#enableCustomColumnFieldset();

      if (this.amountTypeColumnKeyValue) {
        this.#showAmountTypeValueTargets(this.amountTypeColumnKeyValue);
        if (this.amountTypeValueTarget.querySelector("select")?.value) {
          this.#showAmountTypeInflowValueTargets();
        }
      }
    }

    if (amountTypeStrategy === "signed_amount") {
      this.#enableSignedAmountFieldset();
    }
  }

  handleAmountTypeChange(event) {
    const amountTypeColumnKey = event.target.value;

    this.#showAmountTypeValueTargets(amountTypeColumnKey);
    this.#showAmountTypeInflowValueTargets();
  }

  handleAmountTypeIdentifierChange(event) {
    this.#showAmountTypeInflowValueTargets();
  }

  refreshForm(event) {
    clearTimeout(this.refreshTimeout);

    const form = event.target.closest("form");

    this.refreshTimeout = setTimeout(() => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "refresh_only";
      input.value = "true";
      form.appendChild(input);

      // Temporarily disable validation for refresh-only submission
      form.setAttribute("novalidate", "");
      form.requestSubmit();
      form.removeAttribute("novalidate");
    }, 500);
  }

  #showAmountTypeValueTargets(amountTypeColumnKey) {
    const selectableValues = this.#uniqueValuesForColumn(amountTypeColumnKey);

    this.amountTypeValueTarget.classList.remove("hidden");
    this.amountTypeValueTarget.classList.add("flex");

    const select = this.amountTypeValueTarget.querySelector("select");
    const currentValue = select.value;
    select.options.length = 0;
    const fragment = document.createDocumentFragment();

    // Only add the prompt if there's no current value
    if (!currentValue) {
      fragment.appendChild(new Option("Select value", ""));
    }

    selectableValues.forEach((value) => {
      const option = new Option(value, value);
      if (value === currentValue) {
        option.selected = true;
      }
      fragment.appendChild(option);
    });

    select.appendChild(fragment);
  }

  #showAmountTypeInflowValueTargets() {
    // Called when amount_type_identifier_value changes
    // Updates the displayed identifier value in the UI text and shows/hides the inflow value dropdown
    const identifierValueSelect = this.amountTypeValueTarget.querySelector("select");
    const selectedValue = identifierValueSelect.value;

    if (!selectedValue) {
      this.amountTypeInflowValueTarget.classList.add("hidden");
      this.amountTypeInflowValueTarget.classList.remove("flex");
      return;
    }

    // Show the inflow value dropdown
    this.amountTypeInflowValueTarget.classList.remove("hidden");
    this.amountTypeInflowValueTarget.classList.add("flex");

    // Update the displayed identifier value in the text
    const identifierSpan = this.amountTypeInflowValueTarget.querySelector("span.font-medium");
    if (identifierSpan) {
      identifierSpan.textContent = selectedValue;
    }
  }

  #uniqueValuesForColumn(column) {
    const colIdx = this.csvValue[0].indexOf(column);
    const values = this.csvValue.slice(1).map((row) => row[colIdx]);
    return [...new Set(values)];
  }

  // Separate withdrawal/deposit columns replace the single amount column and both
  // amount-type fieldsets, so their fields stop being required while it is selected.
  #toggleSplitColumns(enabled) {
    if (!this.hasSplitColumnsFieldsetTarget) return;

    this.splitColumnsFieldsetTarget.classList.toggle("hidden", !enabled);
    this.#setRequired(this.splitColumnsFieldsetTarget, enabled);

    if (this.hasAmountColumnTarget) {
      this.amountColumnTarget.classList.toggle("hidden", enabled);
      this.#setRequired(this.amountColumnTarget, !enabled);
    }

    if (enabled) {
      for (const fieldset of [
        this.signedAmountFieldsetTarget,
        this.customColumnFieldsetTarget,
      ]) {
        fieldset.classList.add("hidden");
        this.#setRequired(fieldset, false);
      }
    }
  }

  #setRequired(container, required) {
    container.querySelectorAll("select, input").forEach((field) => {
      field.toggleAttribute("required", required);
    });
  }

  #enableCustomColumnFieldset() {
    this.customColumnFieldsetTarget.classList.remove("hidden");
    this.signedAmountFieldsetTarget.classList.add("hidden");

    // Set required on custom column fields
    this.customColumnFieldsetTarget
      .querySelectorAll("select, input")
      .forEach((field) => {
        field.setAttribute("required", "");
      });

    // Remove required from signed amount fields
    this.signedAmountFieldsetTarget
      .querySelectorAll("select, input")
      .forEach((field) => {
        field.removeAttribute("required");
      });
  }

  #enableSignedAmountFieldset() {
    this.customColumnFieldsetTarget.classList.add("hidden");
    this.signedAmountFieldsetTarget.classList.remove("hidden");

    // Hide the inflow value targets when using signed amount strategy
    this.amountTypeValueTarget.classList.add("hidden");
    this.amountTypeValueTarget.classList.remove("flex");
    this.amountTypeInflowValueTarget.classList.add("hidden");
    this.amountTypeInflowValueTarget.classList.remove("flex");
    // Remove required from custom column fields
    this.customColumnFieldsetTarget
      .querySelectorAll("select, input")
      .forEach((field) => {
        field.removeAttribute("required");
      });

    // Set required on signed amount fields
    this.signedAmountFieldsetTarget
      .querySelectorAll("select, input")
      .forEach((field) => {
        field.setAttribute("required", "");
      });
  }
}
