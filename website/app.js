document.addEventListener('DOMContentLoaded', async () => {
    try {
        const response = await fetch('Replace-with-gateway-url/pez-getter');
        const productInfoList = await response.json();

        const productGrid = document.getElementById('productGrid');
        productInfoList.forEach(productInfo => {
            const productCard = document.createElement('div');
            productCard.classList.add('product-card');
            productCard.innerHTML = `
                <h3>${productInfo.productName}</h3>
                <p>${productInfo.description}</p>
                <p>Price: $${productInfo.price}</p>
            `;
            productGrid.appendChild(productCard);
        });
    } catch (error) {
        console.error('Error fetching product information:', error);
        // Handle error display
    }
});