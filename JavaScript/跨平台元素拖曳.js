function draggable(element) {
    let isDragging = false;
    let startX, startY, initialLeft, initialTop;

    const nonDraggableTags = new Set([
        "SELECT", "BUTTON", "INPUT", "TEXTAREA", "A",
        "OPTION", "LABEL", "SUMMARY", "DETAILS", "VIDEO", "CANVAS"
    ]);

    const handlePointerMove = (e) => {
        if (!isDragging) return;
        const dx = e.clientX - startX;
        const dy = e.clientY - startY;
        element.style.left = `${initialLeft + dx}px`;
        element.style.top = `${initialTop + dy}px`;
    };

    const handlePointerUp = () => {
        if (!isDragging) return;
        isDragging = false;
        element.style.cursor = 'auto';
        document.body.style.removeProperty('user-select');

        document.removeEventListener("pointermove", handlePointerMove);
        document.removeEventListener("pointerup", handlePointerUp);
    };

    const handlePointerDown = (e) => {
        if (nonDraggableTags.has(e.target.tagName)) return;
        e.preventDefault();

        isDragging = true;

        startX = e.clientX;
        startY = e.clientY;

        const style = window.getComputedStyle(element);
        initialLeft = parseFloat(style.left) || 0;
        initialTop = parseFloat(style.top) || 0;

        element.style.cursor = 'grabbing';
        document.body.style.userSelect = 'none';

        document.addEventListener("pointermove", handlePointerMove);
        document.addEventListener("pointerup", handlePointerUp);
    };

    element.addEventListener("pointerdown", handlePointerDown);
};