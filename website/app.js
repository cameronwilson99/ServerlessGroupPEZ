document.addEventListener('DOMContentLoaded', async () => {
    try {
        const response = await fetch('https://n41znl1lw5.execute-api.us-east-2.amazonaws.com/pez');
        const productInfoList = await response.json();

        const productGrid = document.getElementById('productGrid');
        productInfoList.forEach(productInfo => {
            const productCard = document.createElement('div');
            productCard.classList.add('product-card');
            productCard.innerHTML = `
                <img src="img/${productInfo.id}.jpeg" width="150" height="150">
                <h3>${productInfo.id}</h3>
                <p>Price: $${productInfo.price}</p>
            `;
            productGrid.appendChild(productCard);
        });
    } catch (error) {
        console.error('Error fetching product information:', error);
        // Handle error display
    }
});