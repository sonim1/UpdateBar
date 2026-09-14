document.querySelectorAll('.ai-install').forEach((section) => {
  const button = section.querySelector('button');
  const prompt = section.querySelector('.ai-install__prompt');
  const status = section.querySelector('[role="status"]');

  button.hidden = false;
  button.addEventListener('click', async () => {
    status.textContent = '';
    try {
      await navigator.clipboard.writeText(prompt.textContent);
      status.textContent = 'Prompt copied. Paste it into your coding agent.';
    } catch {
      prompt.focus();
      const range = document.createRange();
      range.selectNodeContents(prompt);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = 'Copy was blocked. The prompt is selected; use your device’s Copy command.';
    }
  });
});
